import asyncio
import logging
import time
from collections import OrderedDict

import zmq
import zmq.asyncio

logger = logging.getLogger("PyMetaTrader:MT5MQBroker")

HEARTBEAT_LIVENESS = 10  # 3..5 is reasonable
HEARTBEAT_INTERVAL = 5  # Seconds


class _Worker(object):
    expiry: int

    def __init__(self, address: bytes):
        self.address = address
        self.q_response = asyncio.Queue(1)
        self.expiry = time.time() + HEARTBEAT_INTERVAL * HEARTBEAT_LIVENESS

    def expiry_update(self):
        if self.expiry == 0:
            return

        self.expiry = time.time() + HEARTBEAT_INTERVAL * HEARTBEAT_LIVENESS

    async def response(self, msg):
        if self.expiry <= time.time():
            return

        await self.q_response.put(msg)

    async def request(self, socket: zmq.asyncio.Socket, msg):
        request = [self.address, b""] + msg
        print("---> Client request: msg", request)

        await socket.send_multipart(request)

        try:
            response = await asyncio.wait_for(self.q_response.get(), timeout=30)
            self.expiry_update()
        except asyncio.TimeoutError as e:
            self.expiry = 0
            raise e

        return response


class _WorkerQueue(object):
    def __init__(self):
        self._dict = OrderedDict()
        self._queue = asyncio.Queue(100)

    async def ready(self, worker: _Worker):
        self._dict[worker.address] = worker
        await self._queue.put(worker.address)

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

    async def next(self) -> _Worker:
        while True:
            address = await self._queue.get()
            worker = self.get(address)
            if worker:
                if worker.expiry == 0:
                    self._dict.pop(address, None)
                    continue

                return worker

    def get(self, address: bytes) -> _Worker:
        return self._dict.get(address, None)

    def remove(self, address: bytes):
        worker: _Worker = self._dict.pop(address, None)
        if worker:
            worker.expiry = 0


class MT5MQBroker:
    _ctx: zmq.asyncio.Context

    def __init__(self) -> None:
        self._ctx = zmq.asyncio.Context()

    async def start(
        self,
        loop: asyncio.BaseEventLoop | None = None,
        client_url="tcp://127.0.0.1:27027",
        worker_url="tcp://*:28028",
    ):
        if not loop:
            loop = asyncio.get_event_loop()

        client = self._ctx.socket(zmq.ROUTER)
        client.setsockopt(zmq.IDENTITY, b"CBroker")
        client.bind(client_url)
        logger.info("Bind for client connection on %s", client_url)

        worker = self._ctx.socket(zmq.ROUTER)
        worker.setsockopt(zmq.IDENTITY, b"WBroker")
        worker.bind(worker_url)
        logger.info("Bind for worker connection on %s", worker_url)

        workers = _WorkerQueue()

        asyncio.ensure_future(
            self._loop_worker(worker_socket=worker, workers=workers), loop=loop
        )
        asyncio.ensure_future(
            self._loop_client(
                client_socket=client,
                worker_socket=worker,
                workers=workers,
            ),
            loop=loop,
        )

    async def _loop_worker(
        self, worker_socket: zmq.asyncio.Socket, workers: _WorkerQueue
    ):
        while True:
            msg = await worker_socket.recv_multipart()
            if not msg:
                break

            print("---> Worker", msg)
            # Everything after the second (delimiter) frame is reply
            address = msg[0]

            # Forward message to client if it's not a READY
            match msg[2]:
                case b"READY":
                    logger.info("New work connected: %s", msg)
                    await workers.ready(_Worker(address))
                    continue
                case b"CLOSE":
                    logger.info("Close work connection: %s", msg)
                    workers.remove(address)
                    continue
                case _:
                    worker = workers.get(address)
                    if worker:
                        reply = msg[2:]
                        await worker.response(reply)
                    else:
                        logger.warning("Worker %s is not available", address)

                        print(workers._dict)

    async def _loop_client(
        self,
        client_socket: zmq.asyncio.Socket,
        worker_socket: zmq.asyncio.Socket,
        workers: _WorkerQueue,
    ):
        while True:
            msg = await client_socket.recv_multipart()
            if not msg:
                break

            worker = await workers.next()

            asyncio.ensure_future(
                self._task_request(
                    client_socket=client_socket,
                    worker_socket=worker_socket,
                    workers=workers,
                    worker=worker,
                    msg=msg,
                )
            )

    async def _task_request(
        self,
        client_socket: zmq.asyncio.Socket,
        worker_socket: zmq.asyncio.Socket,
        workers: _WorkerQueue,
        worker: _Worker,
        msg: list[bytes],
    ):
        try:
            response = await worker.request(worker_socket, msg)
            await client_socket.send_multipart(response)

            await workers.ready(worker)
        except asyncio.TimeoutError:
            await workers.remove(worker.address)

    async def stop(self):
        self._ctx.destroy()
