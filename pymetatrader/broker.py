import logging
import queue
import threading
import time
from collections import OrderedDict

import zmq

logger = logging.getLogger("PyMetaTrader:MT5MQBroker")

PINGLIVENESS = 10  # 3..5 is reasonable
PING_INTERVAL = 10  # Seconds


class _Worker(object):
    expiry: int
    data: list

    def __init__(self, address: bytes):
        self.address = address
        self.expiry = time.time() + PING_INTERVAL * PINGLIVENESS

    def expiry_update(self):
        if self.expiry == 0:
            return

        self.expiry = time.time() + PING_INTERVAL * PINGLIVENESS

    def is_expired(self) -> bool:
        return self.expiry <= time.time()

    def request(self, data: list, socket: zmq.Socket):
        self.data = data
        self.expiry_update()

        request = [self.address, b""] + data
        socket.send_multipart(request)

        # print("---> Broker request:", request)

    def reply(self, reply, socket: zmq.Socket):
        if not self.data:
            return

        socket.send_multipart(reply)
        self.data = None

        # print("---> Broker reply:", reply[0], reply[2][0:10])


class _WorkerQueue(object):
    def __init__(self, client_socket: zmq.Socket, worker_socket: zmq.Socket):
        self.client_socket: zmq.Socket = client_socket
        self.worker_socket: zmq.Socket = worker_socket
        self.queue: OrderedDict[bytes, _Worker] = OrderedDict()
        self.waiting: OrderedDict[bytes, _Worker] = OrderedDict()

    def ready(self, worker: _Worker):
        self.waiting.pop(worker.address, None)
        self.queue[worker.address] = worker

    def next(self) -> _Worker:
        while True:
            try:
                address, worker = self.queue.popitem()
            except KeyError as e:
                raise TimeoutError() from e

            if not worker.is_expired():
                return worker
            logger.debug("Worker expired: %s %s", address, worker.expiry)

    def remove(self, address: bytes):
        worker: _Worker = self.queue.pop(address, None)
        if worker:
            worker.expiry = 0

    def purge(self):
        if not self.waiting:
            return

        for worker in self.waiting.values():
            if worker.is_expired():
                worker.reply("KO|Expired", self.client_socket)
                self.waiting.pop(worker.address, None)

    def request(
        self,
        request: list,
        address: bytes = None,
        is_wait=False,
        do_raise=True,
    ):
        worker: _Worker = None
        if address:
            if address in self.queue:
                worker = self.queue.pop(address)
            elif is_wait and address in self.waiting:
                worker = self.waiting.pop(address)
            else:
                if do_raise:
                    raise TimeoutError()
                worker = _Worker(address=address)

        if not worker:
            worker = self.next()

        self.waiting[worker.address] = worker
        worker.request(request, socket=self.worker_socket)

    def reply(self, reply: list, address, abandon=True):
        if abandon and address not in self.waiting:
            logger.warning("Abandon worker %s %s", address, reply)
        else:
            worker = self.waiting.pop(address, None)
            if worker:
                worker.reply(reply, self.client_socket)
            else:
                self.client_socket.send_multipart(reply)


class MT5MQBroker:
    _ctx: zmq.Context

    def __init__(self) -> None:
        self._ctx = zmq.Context()

    def start(
        self,
        request_client_url="tcp://*:22880",
        request_worker_url="tcp://*:22990",
        pubsub_client_url="tcp://*:22881",
        pubsub_worker_url="tcp://*:22991",
    ):
        self._start_request(
            client_url=request_client_url,
            worker_url=request_worker_url,
        )

        self._start_xpub_xsub(
            client_url=pubsub_client_url,
            worker_url=pubsub_worker_url,
        )

    def stop(self):
        self._ctx.destroy()

    # REQ/RES
    def _start_request(
        self,
        client_url: str,
        worker_url: str,
    ):
        request_worker_thread = threading.Thread(
            target=self._t_request,
            kwargs=dict(client_url=client_url, worker_url=worker_url),
        )
        request_worker_thread.start()

    def _t_request(self, client_url: str, worker_url: str):
        client_socket: zmq.Socket = self._ctx.socket(zmq.ROUTER)
        client_socket.setsockopt(zmq.IDENTITY, b"CBroker")
        client_socket.setsockopt(zmq.SNDHWM, 10000)
        client_socket.bind(client_url)
        logger.info("REQ listening for client on %s", client_url)

        worker_socket: zmq.Socket = self._ctx.socket(zmq.ROUTER)
        worker_socket.setsockopt(zmq.IDENTITY, b"WBroker")
        worker_socket.setsockopt(zmq.SNDHWM, 10000)
        worker_socket.bind(worker_url)
        logger.info("REQ listening for worker on %s", worker_url)

        poller = zmq.Poller()
        poller.register(client_socket, zmq.POLLIN)
        poller.register(worker_socket, zmq.POLLIN)

        workers = _WorkerQueue(client_socket=client_socket, worker_socket=worker_socket)
        ping_at = time.time() + PING_INTERVAL

        q_requests = queue.Queue(1000)
        q_subcribe_requests = queue.Queue(10000)

        publisher_address = None

        while True:
            socks = dict(poller.poll(PING_INTERVAL * 1000))

            # Worker socket
            if socks.get(worker_socket) == zmq.POLLIN:
                msg = worker_socket.recv_multipart()
                if not msg:
                    break

                address = msg[0]

                match msg[2]:
                    case b"READY":
                        logger.info("New work connected: %s", msg)
                        if publisher_address is None:
                            publisher_address = address
                    case b"PING":
                        logger.info("PONG: %s", msg)
                    case b"CLOSE":
                        logger.info("Close work connection: %s", msg)
                        workers.remove(address)
                        continue
                    case _:
                        reply = msg[2:]
                        workers.reply(reply, address=address)

                try:
                    while True:
                        # Get params
                        request, expiry = None, None
                        if address == publisher_address:
                            try:
                                request, expiry = q_subcribe_requests.get_nowait()
                            except queue.Empty:
                                pass
                        if not request:
                            request, expiry = q_requests.get_nowait()

                        # Check expiry
                        if expiry > time.time():
                            break
                        logger.warning("Expired request: %s", request)

                    # Request
                    workers.request(
                        request,
                        address=address,
                        is_wait=True,
                        do_raise=False,
                    )
                except queue.Empty:
                    workers.ready(_Worker(address=address))

            # Client socket
            if socks.get(client_socket) == zmq.POLLIN:
                msg = client_socket.recv_multipart()
                if not msg:
                    break

                is_subcribe = publisher_address and (
                    msg[2].startswith(b"SUB") or msg[2].startswith(b"UNSUB")
                )

                try:
                    address = publisher_address if is_subcribe else None
                    workers.request(msg, address=address, is_wait=False, do_raise=True)
                except TimeoutError:
                    if is_subcribe:
                        q_subcribe_requests.put((msg, time.time() + 30))
                    else:
                        q_requests.put((msg, time.time() + 30))

            workers.purge()
            # Send ping to idle workers if it's time
            if time.time() >= ping_at:
                try:
                    for _ in range(len(workers.queue)):
                        worker = workers.next()
                        worker.request([b"PING"], socket=worker_socket)
                        ping_at = time.time() + PING_INTERVAL
                except TimeoutError:
                    pass

    # XPUB/XSUB
    def _start_xpub_xsub(self, client_url: str, worker_url: str):
        thread = threading.Thread(
            target=self._t_xpub_xsub,
            kwargs=dict(client_url=client_url, worker_url=worker_url),
        )
        thread.start()

    def _t_xpub_xsub(self, client_url: str, worker_url: str):
        client_socket: zmq.Socket = self._ctx.socket(zmq.XPUB)
        client_socket.setsockopt(zmq.SNDHWM, 10000)
        client_socket.bind(client_url)
        logger.info("XPUB-XSUB listening for client on %s", client_url)

        worker_socket = self._ctx.socket(zmq.XSUB)
        # worker_socket.setsockopt(zmq.SUBSCRIBE, b"")
        worker_socket.bind(worker_url)
        logger.info("XPUB-XSUB listening for worker on %s", worker_url)

        zmq.proxy(client_socket, worker_socket)
