# from pymetatrader import MetaTrader
# from datetime import datetime

# if __name__ == "__main__":
# api = MetaTrader("192.168.0.102")
# # api.history(
# #     "EURUSD",
# #     "M5",
# #     '2020.01.01 00:00:00',
# #     datetime.now().strftime('%Y.%m.%d %H:%M:00'),
# # )

# symbols = api.get_symbols()
# print("symbols ", symbols)

import asyncio

from pymetatrader.broker import MT5MQBroker
from pymetatrader.client import MT5MQClient


async def client_request():
    await asyncio.sleep(5)

    client = MT5MQClient()

    await client.start()

    while True:
        await asyncio.sleep(3)
        print("Client: requested")
        response = await client.request("TIME")
        print("Client: response", response)


async def main():
    loop = asyncio.get_event_loop()

    broker = MT5MQBroker()
    broker.start(loop=loop)

    await client_request()

    # await asyncio.sleep(10000)


asyncio.run(main())
