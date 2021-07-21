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

    def __init__(
        self,
        host,
        push_port=32768,
        pull_port=32769,
        sub_port=32770,
        q=None,
    ):
        self.host = host
        self.push_port = push_port
        self.pull_port = pull_port
        self.sub_port = sub_port
        self.url = "tcp://" + self.host + ":"
        self.q_sub = q

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
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "BARS")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "QUOTES")

        # Bind PUSH Socket to send commands to MetaTrader
        self.push_socket.connect(self.url + str(self.push_port))
        print("[INIT] Ready to send commands to METATRADER (PUSH): " +
              str(self.push_port))

        # Connect PULL Socket to receive command responses from MetaTrader
        self.pull_socket.connect(self.url + str(self.pull_port))
        print("[INIT] Listening for responses from METATRADER (PULL): " +
              str(self.pull_port))

        # Connect SUB Socket to receive market data from MetaTrader
        self.sub_socket.connect(self.url + str(self.sub_port))
        print("[INIT] Listening for market data from METATRADER (SUB): " +
              str(self.sub_port))

        # Initialize POLL set and register PULL and SUB sockets
        self.poller = zmq.Poller()
        self.poller.register(self.pull_socket, zmq.POLLIN)
        self.poller.register(self.sub_socket, zmq.POLLIN)

        self._t_wait()
        self._t_ping()

    def stop(self):
        self.push_socket.close()
        self.pull_socket.close()
        self.sub_socket.close()
        self.poller.unregister(self.pull_socket)
        self.poller.unregister(self.sub_socket)
        self.context.destroy(0)

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

    ### PING
    def _t_ping(self):
        t = threading.Thread(target=self._loop_ping, daemon=False)
        t.start()

    def _loop_ping(self, delay=20):
        while True:
            sleep(delay)
            data = self._request_and_wait(self.push_socket, 'PING')
            if data != "PONG":
                raise RuntimeError("Ping response is invalid")

    ### EVENTS
    def _t_wait(self):
        t = threading.Thread(target=self._loop_wait, daemon=False)
        t.start()

    def _loop_wait(self, timeout=1000):
        # wait for data
        while True:
            sleep(0.1)

            sockets = dict(self.poller.poll(timeout))
            for socket in sockets:
                msg = self._recv(socket)
                if not msg:
                    break

                # print("msg ", msg)
                # sub socket
                if socket == self.sub_socket:
                    type, data = msg.split(" ", 1)
                    data = self._parse_subcribe_data(type, data)
                    self.q_sub.put((type, data))
                    continue

                # pull socket
                try:
                    type, id, data = msg.split("|", 2)
                    if id in self.waiters:
                        self.waiters[id].put(data)
                    else:
                        print("Abandoned message: ", msg)
                except Exception as e:
                    print("Wait data error: ", e)

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

    def _parse_subcribe_data(self, type, data):
        if type == "BARS":
            result = []
            raws = data.split(";")
            for raw in raws:
                symbol, timeframe, bar = raw.split("|", 2)
                bar = self._parse_bar(bar)
                result.append((symbol, timeframe, bar))
            return result

        if type == "QUOTES":
            result = []
            raws = data.split(";")
            for raw in raws:
                quote = self._parse_market(raw)
                result.append(quote)
            return result

        if type == "ORDERS":
            result = []
            raws = data.split(";")
            for raw in raws:
                event, order = raw.split("|", 2)
                order = self._parse_trade(order)
                order['status'] = event
                result.append(order)
            return result

        raise RuntimeError(f"Cannot parse subscribe data: {type} {data}")

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
    def subscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'SUB_BARS', request)
        return data == "OK"

    def unsubscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'UNSUB_BARS', request)
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

            bar = self._parse_bar(raw)
            bars.append(bar)
        return bars

    def _parse_bar(self, raw):
        bar = raw.split('|')
        bar[0] = self._parse_datetime(bar[0])
        for i in range(1, len(bar)):
            bar[i] = float(bar[i])
        return bar

    # symbols
    def get_markets(self):
        data = self._request_and_wait(self.push_socket, 'MARKETS')
        return self._parse_markets(data)

    def _parse_markets(self, data):
        raws = data.split(';')
        markets = []
        for raw in raws:
            markets.append(self._parse_market(raw))
        return markets

    # SYMBOL|SYMBOL_DESCRIPTION|SYMBOL_CURRENCY_BASE|MODE_LOW|MODE_HIGH|MODE_BID|MODE_ASK|MODE_POINT|MODE_DIGITS|MODE_SPREAD|MODE_TICKSIZE|MODE_MINLOT|MODE_LOTSTEP|MODE_MAXLOT
    _markets_keys = [['symbol', str], ['description', str], ['currency', str],
                     ['low', float], ['high', float], ['bid', float],
                     ['ask', float], ['point', float], ['digits', float],
                     ['spread', float], ['ticksize', float], ['minlot', float],
                     ['lotstep', float], ['maxlot', float]]

    def _parse_market(self, data):
        try:
            raw = data.split('|')
            market = dict()
            for i in range(0, len(self._markets_keys)):
                key = self._markets_keys[i][0]
                type = self._markets_keys[i][1]
                market[key] = type(raw[i])
            return market
        except:
            raise RuntimeError(f"Cannot parse market data: {data}")

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

    def subscribe_quotes(self, symbol):
        data = self._request_and_wait(self.push_socket, 'SUB_QUOTES', symbol)
        return data == "OK"

    def unsubscribe_quotes(self, symbol):
        data = self._request_and_wait(self.push_socket, 'UNSUB_QUOTES', symbol)
        return data == "OK"

    ### ACCOUNT
    # fund
    def get_fund(self):
        data = self._request_and_wait(self.push_socket, 'FUND')
        return self._parse_fund(data)

    # trades
    def get_open_orders(self):
        data = self._request_and_wait(self.push_socket, 'ORDERS')
        return self._parse_trades(data)

    def get_trades(self, symbol=''):
        data = self._request_and_wait(self.push_socket, 'TRADES', symbol)
        return self._parse_trades(data)

    def _parse_trades(self, data):
        raws = data.split(';')
        trades = []
        for raw in raws:
            if not raw:
                continue

            trade = self._parse_trade(raw)
            trades.append(trade)
        return trades

    def _parse_trade(self, raw):
        trade = raw.split('|')
        # TICKET|SYMBOL|TYPE|PRICE|LOT|TIME|SL|TP|PNL|COMMISSION|SWAP|COMMENT
        return dict(
            ticket=int(trade[0]),
            symbol=trade[1],
            type=trade[2],
            price=float(trade[3]),
            lots=float(trade[4]),
            time=self._parse_datetime(trade[5]),
            sl=float(trade[6]),
            tp=float(trade[7]),
            pnl=float(trade[8]),
            commission=float(trade[9]),
            swap=float(trade[10]),
            comment=trade[11],
        )

    # orders
    def open_order(self, symbol, type, lots, price, sl=0, tp=0, comment=''):
        request = f"{symbol};{type};{lots};{price};{sl};{tp};{comment}"
        ticket = self._request_and_wait(self.push_socket, 'OPEN_ORDER',
                                        request)
        return int(ticket)

    def modify_order(self, ticket, price, sl=0, tp=0, expiration=0):
        request = f"{ticket};{price};{sl};{tp};{expiration}"
        data = self._request_and_wait(self.push_socket, 'MODIFY_ORDER',
                                      request)
        if data != "OK":
            raise RuntimeError(f"Modify order {ticket} error: {data}")
        return True

    def close_order(self, ticket):
        data = self._request_and_wait(self.push_socket, 'CLOSE_ORDER', ticket)
        if data != "OK":
            raise RuntimeError(f"Modify order {ticket} error: {data}")
        return True

    ### helpers
    def _parse_datetime(self, raw):
        dt = datetime.strptime(raw, '%Y.%m.%d %H:%M:%S')
        return dt.replace(tzinfo=timezone.utc).timestamp() * 1000