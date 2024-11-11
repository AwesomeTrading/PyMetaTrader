import asyncio
import logging
from typing import Callable

import zmq
import zmq.asyncio

logger = logging.getLogger("PyMetaTrader:MT5MQClient")


class MT5MQClient:
    _ctx: zmq.asyncio.Context
    _queue: asyncio.Queue

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
            request_socket = self._ctx.socket(zmq.REQ)
            request_socket.setsockopt(zmq.IDENTITY, f"Client-{i}".encode())
            request_socket.connect(request_url)
            await self._queue.put(request_socket)

        logger.info("Initialized %d request concurrencies to %s", size, request_url)

        # Subscriber
        sub_socket = self._ctx.socket(zmq.SUB)
        sub_socket.connect(subscribe_url)
        sub_socket.setsockopt(zmq.SUBSCRIBE, b"")
        logger.info("Connecting to publicer %s", subscribe_url)

        asyncio.ensure_future(
            self._loop_subcribe(socket=sub_socket, callback=subscribe_callback)
        )

    async def stop(self):
        self._ctx.destroy()

    async def request(self, *params) -> str:
        # Get socket
        socket: zmq.asyncio.Socket = await self._queue.get()

        # Send
        await socket.send_multipart(params)
        response = await socket.recv_string()

        # Restore socket
        await self._queue.put(socket)

        return response

    async def _loop_subcribe(self, socket: zmq.asyncio.Socket, callback: Callable):
        while True:
            msg = await socket.recv()
            asyncio.ensure_future(callback(msg))