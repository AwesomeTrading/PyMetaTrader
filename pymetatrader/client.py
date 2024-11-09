import asyncio
import logging

import zmq
import zmq.asyncio

logger = logging.getLogger("PyMetaTrader:MT5MQClient")


class MT5MQClient:
    _ctx: zmq.asyncio.Context
    _queue: asyncio.Queue

    def __init__(self) -> None:
        self._ctx = zmq.asyncio.Context()
        self._queue = asyncio.Queue(100)

    async def start(self, request_url="tcp://127.0.0.1:27027", size=5) -> None:
        for i in range(0, size):
            socket = self._ctx.socket(zmq.REQ)
            socket.setsockopt(zmq.IDENTITY, f"Client-{i}".encode())
            socket.connect(request_url)
            await self._queue.put(socket)

        logger.info("Initialized %d concurrencies", size)

    async def request(self, *params) -> str:
        # Get socket
        socket: zmq.asyncio.Socket = await self._queue.get()

        # Send
        await socket.send_multipart(params)
        response = await socket.recv_string()

        # Restore socket
        await self._queue.put(socket)

        print("response", response)

        return response

    async def stop(self):
        self._ctx.destroy()
