import asyncio
import logging
import time
from typing import Callable

import zmq
import zmq.asyncio

logger = logging.getLogger("PyMetaTrader:MT5MQClient")


class MT5MQClient:
    def __init__(self) -> None:
        self._ctx = zmq.asyncio.Context()
        self._queue = asyncio.Queue(100)

    async def start(
        self,
        request_url="tcp://127.0.0.1:22880",
        subscribe_url="tcp://127.0.0.1:22881",
        subscribe_callback: Callable = None,
        size=5,
    ) -> None:
        # Requester
        for i in range(0, size):
            await self._new_loop_request(request_url=request_url, id=i)
        logger.info("Initialized %d request concurrencies to %s", size, request_url)

        asyncio.ensure_future(
            self._loop_subcribe(
                subscribe_url=subscribe_url, callback=subscribe_callback
            )
        )

    async def stop(self):
        self._ctx.destroy()

    async def request(self, *params, timeout=30) -> str:
        expiry = time.time() + timeout
        future = asyncio.Future()
        await self._queue.put((params, future, expiry))
        return await future

    async def _new_loop_request(self, request_url: str, id: int):
        asyncio.ensure_future(self._loop_request(request_url=request_url, id=id))

    async def _loop_request(self, request_url: str, id: int):
        ctx = zmq.asyncio.Context.instance()
        request_socket: zmq.asyncio.Socket = ctx.socket(zmq.REQ)
        request_socket.setsockopt(zmq.IDENTITY, f"Client-{id}".encode())
        request_socket.connect(request_url)
        logger.info("Initialized request socket %s", request_url)

        while True:
            params, future, expiry = await self._queue.get()
            await request_socket.send_multipart(params)

            try:
                async with asyncio.timeout(expiry - time.time()):
                    response = await request_socket.recv_string()
                    future.set_result(response)
            except asyncio.TimeoutError:
                logger.warning("Request expired: %s", params)
                future.set_result("KO|Request expired")
                request_socket.close()
                await self._new_loop_request(request_url=request_url, id=id)
                break

        logger.warning("Loop request %d died", id)

    async def _loop_subcribe(self, subscribe_url: str, callback: Callable):
        sub_socket = self._ctx.socket(zmq.SUB)
        sub_socket.connect(subscribe_url)
        sub_socket.setsockopt(zmq.SUBSCRIBE, b"")
        logger.info("Connecting to publisher %s", subscribe_url)

        while True:
            msg = await sub_socket.recv()
            asyncio.ensure_future(callback(msg))

        logger.warning("Loop subscribe died")
