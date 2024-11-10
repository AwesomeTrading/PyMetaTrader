import asyncio
import logging
import queue
import threading
import time
from collections import OrderedDict

import zmq

logger = logging.getLogger("PyMetaTrader:MT5MQBroker")

HEARTBEAT_LIVENESS = 10  # 3..5 is reasonable
HEARTBEAT_INTERVAL = 10  # Seconds


class _Worker(object):
    expiry: int

    def __init__(self, address: bytes, socket: zmq.Socket):
        self.address = address
        self.socket = socket
        self.q_response = queue.Queue(1)
        self.expiry = time.time() + HEARTBEAT_INTERVAL * HEARTBEAT_LIVENESS

    def expiry_update(self):
        if self.expiry == 0:
            return

        self.expiry = time.time() + HEARTBEAT_INTERVAL * HEARTBEAT_LIVENESS

    def is_expired(self) -> bool:
        return self.expiry <= time.time()

    def response(self, msg):
        if self.expiry <= time.time():
            logger.warning("Response on expired worker: %s, %s", self.expiry, msg)
            return

        self.q_response.put(msg)

    def request(self, msg: list | bytes, timeout: int = 10):
        request = [self.address, b""] + msg

        self.socket.send_multipart(request)

        try:
            self.expiry_update()
            response = self.q_response.get(timeout=timeout)
        except queue.Empty as e:
            self.expiry = 0
            raise TimeoutError() from e

        return response


class _WorkerQueue(object):
    def __init__(self):
        self._dict = OrderedDict()
        self._queue = queue.Queue(100)

    def ready(self, worker: _Worker):
        self._dict[worker.address] = worker
        self._queue.put(worker.address)

    # def purge(self):
    #     """Look for & kill expired workers."""
    #     t = time.time()
    #     expired = []
    #     for address, worker in self._dict.items():
    #         if t < worker.expiry:  # Worker is alive
    #             break
    #         expired.append(address)
    #     for address in expired:
    #         print("W: Idle worker expired: %s" % address)
    #         self.remove(address)

    def next(self, timeout: int | float = None) -> _Worker:
        while True:
            try:
                address = self._queue.get(timeout=timeout)
            except queue.Empty as e:
                raise TimeoutError() from e

            worker = self.get(address)
            if worker:
                if not worker.is_expired():
                    return worker
                logger.debug("Worker expired: %s %s", address, worker.expiry)
                self._dict.pop(address, None)

    def get(self, address: bytes) -> _Worker:
        return self._dict.get(address, None)

    def remove(self, address: bytes):
        worker: _Worker = self._dict.pop(address, None)
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
        client = self._ctx.socket(zmq.ROUTER)
        client.setsockopt(zmq.IDENTITY, b"CBroker")
        client.bind(client_url)
        logger.info("REQ listening for client on %s", client_url)

        worker = self._ctx.socket(zmq.ROUTER)
        worker.setsockopt(zmq.IDENTITY, b"WBroker")
        worker.bind(worker_url)
        logger.info("REQ listening for worker on %s", worker_url)

        workers = _WorkerQueue()

        # Theads
        request_worker_thread = threading.Thread(
            target=self._loop_request_worker,
            kwargs=dict(worker_socket=worker, workers=workers),
        )
        request_client_thread = threading.Thread(
            target=self._loop_request_client,
            kwargs=dict(client_socket=client, workers=workers),
        )
        request_worker_ping = threading.Thread(
            target=self._loop_request_worker_ping,
            kwargs=dict(workers=workers),
        )

        request_worker_thread.start()
        request_client_thread.start()
        request_worker_ping.start()

    def _loop_request_worker(self, worker_socket: zmq.Socket, workers: _WorkerQueue):
        while True:
            msg = worker_socket.recv_multipart()
            if not msg:
                break

            address = msg[0]

            match msg[2]:
                case b"READY":
                    logger.info("New work connected: %s", msg)
                    workers.ready(_Worker(address=address, socket=worker_socket))
                case b"CLOSE":
                    logger.info("Close work connection: %s", msg)
                    workers.remove(address)
                case _:
                    worker = workers.get(address)
                    if worker:
                        reply = msg[2:]
                        worker.response(reply)
                    else:
                        logger.warning("Worker %s is not available", address)

    def _loop_request_client(
        self,
        client_socket: zmq.Socket,
        workers: _WorkerQueue,
    ):
        while True:
            msg = client_socket.recv_multipart()
            if not msg:
                break

            try:
                worker = workers.next(timeout=30)

                thread = threading.Thread(
                    target=self._task_request,
                    kwargs=dict(
                        client_socket=client_socket,
                        workers=workers,
                        worker=worker,
                        msg=msg,
                    ),
                )
                thread.start()
            except TimeoutError:
                client_socket.send_multipart([msg[0], msg[1], b"KO|Timout waiting for worker"])

    def _task_request(
        self,
        client_socket: zmq.Socket,
        workers: _WorkerQueue,
        worker: _Worker,
        msg: list[bytes],
    ):
        try:
            response = worker.request(msg)
            client_socket.send_multipart(response)
            workers.ready(worker)
        except TimeoutError:
            workers.remove(worker.address)
            client_socket.send_multipart([msg[0], msg[1], b"KO|Timout waiting for worker"])

    def _loop_request_worker_ping(self, workers: _WorkerQueue):
        while True:
            time.sleep(10)
            worker = workers.next()

            try:
                response = worker.request([b"", b"", b"PING"], timeout=3)
                if response:
                    logger.debug("PONG: %s", response)
                    workers.ready(worker)
            except TimeoutError:
                logger.warning("Worker %s dead", worker.address)
                worker.expiry = 0

    # XPUB/XSUB
    def _start_xpub_xsub(
        self,
        client_url: str,
        worker_url: str,
    ):
        client_socket = self._ctx.socket(zmq.XPUB)
        client_socket.bind(client_url)
        logger.info("XPUB-XSUB listening for client on %s", client_url)

        worker_socket = self._ctx.socket(zmq.XSUB)
        # worker_socket.setsockopt(zmq.SUBSCRIBE, b"")
        worker_socket.bind(worker_url)
        logger.info("XPUB-XSUB listening for worker on %s", worker_url)

        thread = threading.Thread(
            target=self._loop_xpub_xsub,
            kwargs=dict(client_socket=client_socket, worker_socket=worker_socket),
        )
        thread.start()

    def _loop_xpub_xsub(
        self,
        client_socket: zmq.Socket,
        worker_socket: zmq.Socket,
    ):
        zmq.proxy(client_socket, worker_socket)
