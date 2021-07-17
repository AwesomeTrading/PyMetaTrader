import zmq
import queue
import threading
import random
import string
from datetime import datetime, timezone
from time import sleep


def random_id(length=6):
    return ''.join(random.SystemRandom().choice(string.ascii_uppercase +
                                                string.digits)
                   for _ in range(length))


class MetaTrader():
    wait_timeout = 5000
    waiters = dict()

    def __init__(self, host, push_port=32768, pull_port=32769, sub_port=32770):
        self.host = host
        self.push_port = push_port
        self.pull_port = pull_port
        self.sub_port = sub_port
        self.url = "tcp://" + self.host + ":"

        # ZeroMQ Context
        self.context = zmq.Context()

        # Create Sockets
        self.push_socket = self.context.socket(zmq.PUSH)
        self.push_socket.setsockopt(zmq.SNDHWM, 1)
        # self.push_socket_status = {'state': True, 'latest_event': 'N/A'}

        self.pull_socket = self.context.socket(zmq.PULL)
        self.pull_socket.setsockopt(zmq.RCVHWM, 1)
        # self.pull_socket_status = {'state': True, 'latest_event': 'N/A'}

        self.sub_socket = self.context.socket(zmq.SUB)

        # Bind PUSH Socket to send commands to MetaTrader
        self.push_socket.connect(self.url + str(self.push_port))
        print("[INIT] Ready to send commands to METATRADER (PUSH): " +
              str(self.push_port))

        # Connect PULL Socket to receive command responses from MetaTrader
        self.pull_socket.connect(self.url + str(self.pull_port))
        print("[INIT] Listening for responses from METATRADER (PULL): " +
              str(self.pull_port))

        # Connect SUB Socket to receive market data from MetaTrader
        print("[INIT] Listening for market data from METATRADER (SUB): " +
              str(self.sub_port))
        self.sub_socket.connect(self.url + str(self.sub_port))

        # Initialize POLL set and register PULL and SUB sockets
        self.poller = zmq.Poller()
        self.poller.register(self.pull_socket, zmq.POLLIN)
        self.poller.register(self.sub_socket, zmq.POLLIN)

        self._t_wait()

    def stop(self):
        self.push_socket.close()
        self.pull_socket.close()
        self.sub_socket.close()
        self.context.destroy()

    def _send(self, socket, data):
        # if self._PUSH_SOCKET_STATUS['state'] == True:
        try:
            socket.send_string(data, zmq.DONTWAIT)
        except zmq.error.Again:
            print("Resource timeout.. please try again.")
        # else:
        #     print('\n[KERNEL] NO HANDSHAKE ON PUSH SOCKET.. Cannot SEND data')

    def _recv(self, socket) -> str:
        # if self._PULL_SOCKET_STATUS['state'] == True:
        try:
            return socket.recv_string(zmq.DONTWAIT)
        except zmq.error.Again:
            print("Resource timeout.. please try again.")
        # else:
        #     print('\r[KERNEL] NO HANDSHAKE ON PULL SOCKET.. Cannot READ data', end='', flush=True)

        return None

    def _t_wait(self):
        t = threading.Thread(target=self._loop_wait, daemon=False)
        t.start()

    def _loop_wait(self, timeout=1000):
        while True:
            sleep(0.1)

            sockets = dict(self.poller.poll(timeout))
            for socket in sockets:
                try:
                    msg = self._recv(socket)

                    if not msg:
                        break

                    datas = msg.split("|", 2)
                    print("datas ", datas)
                    id = datas[1]
                    data = datas[2]
                    if id in self.waiters:
                        self.waiters[id].put(data)
                    else:
                        print("Abandoned message: ", msg)
                except Exception as e:
                    print("Wait data error: ", e)
                # except zmq.error.Again:
                #     pass  # resource temporarily unavailable, nothing to print
                # except ValueError:
                #     pass  # No data returned, passing iteration.
                # except UnboundLocalError:
                #     pass  # _symbol may sometimes get referenced before being assigned.

    def _request(self, socket, action, msg=''):
        request_id = random_id()
        request = "{};{};{}".format(action, request_id, msg)
        self._send(socket, request)

        q = queue.Queue()
        self.waiters[request_id] = q
        return request_id, q

    def _request_and_wait(self, socket, action, msg=''):
        id, q = self._request(socket, action, msg)
        try:
            return q.get(timeout=self.wait_timeout)
        except queue.Empty:
            raise RuntimeError("No data response")
        finally:
            del self.waiters[id]

    ### MARKETS
    # time
    def get_time(self):
        data = self._request_and_wait(self.push_socket, 'TIME')
        return int(data)

    def _parse_fund(self, data):
        raw = data.split('|')
        return dict(
            cash=float(raw[0]),
            value=float(raw[1]),
        )

    # bars
    def unsubscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'UNSUB_BARS', request)
        return data == "OK"

    def subscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'SUB_BARS', request)
        return data == "OK"

    def get_bars(self, symbol, timeframe, start, end):
        start = datetime.fromtimestamp(start / 1000)
        start = start.strftime('%Y.%m.%d %H:%M:00')

        end = datetime.fromtimestamp(end / 1000)
        end = end.strftime('%Y.%m.%d %H:%M:00')

        request = "{};{};{};{}".format(symbol, timeframe, start, end)
        data = self._request_and_wait(self.push_socket, 'HISTORY', request)
        return self._parse_bars(data)

    def _parse_bars(self, data):
        data = data.split('|', 2)[2]
        raws = data.split(';')
        bars = []
        for raw in raws:
            if not raw:
                continue

            bar = raw.split('|')
            # bar time
            bar_time = datetime.strptime(bar[0], '%Y.%m.%d %H:%M:%S')
            bar[0] = bar_time.replace(tzinfo=timezone.utc).timestamp() * 1000

            bars.append(bar)
        return bars

    # symbols
    def get_markets(self):
        data = self._request_and_wait(self.push_socket, 'MARKETS')
        return self._parse_markets(data)

    # SYMBOL|SYMBOL_DESCRIPTION|SYMBOL_CURRENCY_BASE|MODE_LOW|MODE_HIGH|MODE_BID|MODE_ASK|MODE_POINT|MODE_DIGITS|MODE_SPREAD|MODE_TICKSIZE|MODE_MINLOT|MODE_LOTSTEP|MODE_MAXLOT
    _markets_keys = [['symbol', str], ['description', str], ['currency', str],
                     ['low', float], ['high', float], ['bid', float],
                     ['ask', float], ['point', float], ['digits', float],
                     ['spread', float], ['ticksize', float], ['minlot', float],
                     ['lotstep', float], ['maxlot', float]]

    def _parse_markets(self, data):
        raws = data.split(';')
        markets = []
        for raw in raws:
            raw = raw.split('|')
            market = dict()
            for i in range(0, len(self._markets_keys)):
                key = self._markets_keys[i][0]
                type = self._markets_keys[i][1]
                market[key] = type(raw[i])
            markets.append(market)
        return markets

    # quote
    def get_quotes(self, symbols=[]):
        markets = self.get_markets()
        if not symbols:
            return markets

        results = []
        for market in markets:
            if market['symbol'] in symbols:
                results.append(market)
        return results

    ### ACCOUNT
    # fund
    def get_fund(self):
        data = self._request_and_wait(self.push_socket, 'FUND')
        return self._parse_fund(data)

    # trades
    def get_open_orders(self):
        data = self._request_and_wait(self.push_socket, 'ORDERS')
        return self._parse_trades(data)

    def get_trades(self, symbol, mode='OP_BUY|OP_SELL'):
        data = self._request_and_wait(self.push_socket, 'TRADES', symbol)
        return self._parse_trades(data)

    def _parse_trades(self, data):
        raws = data.split(';')
        trades = []
        for raw in raws:
            if not raw:
                continue

            trade = raw.split('|')

            # TICKET|SYMBOL|TYPE|PRICE|LOT|TIME|SL|TP|PNL|COMMISSION|SWAP|COMMENT
            trades.append(
                dict(
                    ticket=int(trade[0]),
                    symbol=trade[1],
                    type=trade[2],
                    price=float(trade[3]),
                    lots=float(trade[4]),
                    time=trade[5],
                    sl=float(trade[6]),
                    tp=float(trade[7]),
                    pnl=float(trade[8]),
                    commission=float(trade[9]),
                    swap=float(trade[10]),
                    comment=trade[11],
                ))
        return trades
