from pymetatrader import MetaTraderAPI
from datetime import datetime

if __name__ == '__main__':
    api = MetaTraderAPI("192.168.0.102")
    api.history(
        "EURUSD",
        "M5",
        '2020.01.01 00:00:00',
        datetime.now().strftime('%Y.%m.%d %H:%M:00'),
    )
