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

    def __init__(self, address: bytes):
        self.address = address
        self.expiry = time.time() + PING_INTERVAL * PINGLIVENESS

    def expiry_update(self):
        if self.expiry == 0:
            return

        self.expiry = time.time() + PING_INTERVAL * PINGLIVENESS

    def is_expired(self) -> bool:
        return self.expiry <= time.time()


class _WorkerQueue(object):
    def __init__(self):
        self.queue: OrderedDict[bytes, _Worker] = OrderedDict()

    def ready(self, worker: _Worker):
        self.queue[worker.address] = worker

    def next(self) -> _Worker:
        while True:
            try:
                address, worker = self.queue.popitem()
            except KeyError as e:
                raise TimeoutError() from e

            if worker:
                if not worker.is_expired():
                    return worker
                logger.debug("Worker expired: %s %s", address, worker.expiry)

    def remove(self, address: bytes):
        worker: _Worker = self.queue.pop(address, None)
        if worker:
            worker.expiry = 0


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

        workers = _WorkerQueue()
        ping_at = time.time() + PING_INTERVAL

        q_requests = queue.Queue(10000)

        while True:
            socks = dict(poller.poll(PING_INTERVAL * 1000))

            if socks.get(worker_socket) == zmq.POLLIN:
                msg = worker_socket.recv_multipart()
                if not msg:
                    break

                address = msg[0]

                match msg[2]:
                    case b"READY":
                        logger.info("New work connected: %s", msg)
                    case b"PING":
                        logger.info("PONG: %s", msg)
                        continue
                    case b"CLOSE":
                        logger.info("Close work connection: %s", msg)
                        workers.remove(address)
                        continue
                    case _:
                        reply = msg[2:]
                        client_socket.send_multipart(reply)

                try:
                    request = [address, b""] + q_requests.get_nowait()
                    worker_socket.send_multipart(request)
                except queue.Empty:
                    workers.ready(_Worker(address=address))

            if socks.get(client_socket) == zmq.POLLIN:
                msg = client_socket.recv_multipart()
                if not msg:
                    break

                try:
                    worker = workers.next()
                    request = [worker.address, b""] + msg
                    worker_socket.send_multipart(request)
                except TimeoutError:
                    q_requests.put(msg)

            # Send ping to idle workers if it's time
            if time.time() >= ping_at:
                for worker in workers.queue:
                    msg = [worker, b"", b"PING"]
                    worker_socket.send_multipart(msg)
                ping_at = time.time() + PING_INTERVAL

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
