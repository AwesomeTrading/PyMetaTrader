import asyncio
import logging

import zmq
import zmq.asyncio

logger = logging.getLogger("PyMetaTrader:MT5MQBroker")


class MT5MQBroker:
    _ctx: zmq.asyncio.Context

    def __init__(self) -> None:
        self._ctx = zmq.asyncio.Context()

    def start(
        self,
        loop: asyncio.BaseEventLoop | None = None,
        client_url="tcp://127.0.0.1:27027",
        worker_url="tcp://*:28028",
    ):
        asyncio.ensure_future(
            self._loop_client_worker(
                client_url=client_url,
                worker_url=worker_url,
            ),
            loop=loop,
        )

    async def _loop_client_worker(self, client_url: str, worker_url: str):
        client = self._ctx.socket(zmq.ROUTER)
        client.setsockopt(zmq.IDENTITY, b"CBroker")
        client.bind(client_url)
        logger.info("Bind for client connection on %s", client_url)

        worker = self._ctx.socket(zmq.ROUTER)
        worker.setsockopt(zmq.IDENTITY, b"WBroker")
        worker.bind(worker_url)
        logger.info("Bind for worker connection on %s", worker_url)

        sem = asyncio.Semaphore(1)

        while True:
            msg = await worker.recv_multipart()
            if not msg:
                break

            # Everything after the second (delimiter) frame is reply
            reply = msg[2:]

            # Forward message to client if it's not a READY
            if reply[0] != b"READY":
                await client.send_multipart(reply, flags=zmq.Flag.DONTWAIT)
            else:
                print("New work connected:", msg)

            # Handle msg
            address = msg[0]

            asyncio.ensure_future(
                self._wait_client_request(
                    address=address,
                    client=client,
                    worker=worker,
                    sem=sem,
                )
            )

    async def _wait_client_request(
        self,
        address: bytes,
        client: zmq.asyncio.Socket,
        worker: zmq.asyncio.Socket,
        sem: asyncio.Semaphore,
    ):
        await sem.acquire()
        try:
            msg = await client.recv_multipart()
        finally:
            sem.release()

        request = [address, b""] + msg
        print("Sem: msg", request)
        await worker.send_multipart(request, flags=zmq.Flag.DONTWAIT)

    async def stop(self):
        self._ctx.destroy()
