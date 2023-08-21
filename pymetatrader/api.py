import zmq
import queue
import threading
import random
import string
from datetime import datetime, timezone
from time import sleep


def random_id(length=6):
    return "".join(
        random.SystemRandom().choice(string.ascii_uppercase + string.digits)
        for _ in range(length)
    )


class MetaTrader:
    wait_timeout = 10000
    waiters = dict()
    q_sub: queue.Queue

    def __init__(
        self,
        host,
        push_port=30001,
        pull_port=30002,
        sub_port=30003,
        q=None,
    ):
        url = f"tcp://{host}:"
        self.q_sub = q
        self.markets = dict()

        # ZeroMQ Context
        self.context = zmq.Context()

        # Create Sockets
        # Bind PUSH Socket to send commands to MetaTrader
        self.push_socket = self.context.socket(zmq.PUSH)
        self.push_socket.setsockopt(zmq.SNDHWM, 1)
        self.push_socket.connect(f"{url}{push_port}")
        print(f"[INIT] Connecting to METATRADER (PUSH): {push_port}")

        # Connect PULL Socket to receive command responses from MetaTrader
        self.pull_socket = self.context.socket(zmq.PULL)
        self.pull_socket.setsockopt(zmq.RCVHWM, 1)
        self.pull_socket.connect(f"{url}{pull_port}")
        print(f"[INIT] Connecting to METATRADER (PULL): {pull_port}")

        # Connect SUB Socket to receive market data from MetaTrader
        self.sub_socket = self.context.socket(zmq.SUB)
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "BARS")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "QUOTES")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "REFRESH")
        self.sub_socket.connect(f"{url}{sub_port}")
        print(f"[INIT] Connecting to METATRADER (SUB): {sub_port}")

        # Initialize POLL set and register PULL and SUB sockets
        self.poller = zmq.Poller()
        self.poller.register(self.pull_socket, zmq.POLLIN)
        self.poller.register(self.sub_socket, zmq.POLLIN)

        self._t_wait()
        self._t_ping()

        # Sleep to waiting for connection completed
        sleep(1)

    def stop(self):
        self.push_socket.close()
        self.pull_socket.close()
        self.sub_socket.close()
        self.poller.unregister(self.pull_socket)
        self.poller.unregister(self.sub_socket)
        self.context.destroy(0)

    def _send(self, socket, data):
        return socket.send_string(data)

    def _recv(self, socket) -> str:
        try:
            return socket.recv_string(zmq.NOBLOCK)
        except zmq.error.Again:
            print("Resource timeout.. please try again.")

    # PING
    def _t_ping(self):
        t = threading.Thread(target=self._loop_ping, daemon=False)
        t.start()

    def _loop_ping(self, delay=20):
        while True:
            sleep(delay)
            data = self._request_and_wait(self.push_socket, "PING")
            if data != "PONG":
                raise RuntimeError("Ping response is invalid")

    # EVENTS
    def _t_wait(self):
        t = threading.Thread(target=self._loop_wait, daemon=False)
        t.start()

    def _loop_wait(self, timeout=1000):
        # wait for data
        while True:
            sleep(0.1)

            sockets = dict(self.poller.poll(timeout))
            for socket in sockets:
                try:
                    msg = self._recv(socket)
                    if not msg:
                        continue

                    # print("---> msg ", msg)
                    # sub socket
                    if socket == self.sub_socket:
                        type, data = msg.split(" ", 1)
                        data = self._parse_subcribe_data(type, data)
                        self.q_sub.put((type, data))
                        continue

                    # pull socket
                    ok, id, data = msg.split("|", 2)
                    if id in self.waiters:
                        self.waiters[id].put((ok == "OK", data))
                    else:
                        print("Abandoned message: ", msg)
                except Exception as e:
                    print("Wait socket data error: ", e, msg)

    def _request(self, socket, action, msg=""):
        request_id = random_id()
        request = "{};{};{}".format(action, request_id, msg)
        self._send(socket, request)

        q = queue.Queue()
        self.waiters[request_id] = q
        return request_id, q

    def _request_and_wait(self, socket, action, msg=""):
        id, q = self._request(socket, action, msg)
        try:
            ok, data = q.get(timeout=self.wait_timeout)
        except queue.Empty:
            raise RuntimeError(f"No data response for request: {action} {msg}")
        finally:
            del self.waiters[id]

        if not ok:
            raise RuntimeError(f"Error request[{action} {msg}]: {data}")
        return data

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
            return self._parse_quotes(data)

        if type == "REFRESH":
            raws = data.split("\n")
            history_orders = []
            history_deals = []
            orders = []
            trades = []
            for raw in raws:
                event, data = raw.split(" ", 1)
                if not data:
                    continue
                if event == "HISTORY_ORDERS":
                    history_orders.extend(self._parse_orders(data))
                elif event == "HISTORY_DEALS":
                    history_deals.extend(self._parse_deals(data))
                elif event == "ORDERS":
                    orders.extend(self._parse_orders(data))
                elif event == "TRADES":
                    trades.extend(self._parse_trades(data))

            return dict(
                history_orders=history_orders,
                history_deals=history_deals,
                orders=orders,
                trades=trades,
            )

        raise RuntimeError(f"Cannot parse subscribe data: {type} {data}")

    # MARKETS
    # time
    def get_time(self):
        data = self._request_and_wait(self.push_socket, "TIME")
        return float(data)

    # bars
    def subscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, "SUB_BARS", request)
        return True

    def unsubscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, "UNSUB_BARS", request)
        return True

    def get_bars(self, symbol, timeframe, start, end):
        request = "{};{};{};{}".format(symbol, timeframe, start / 1000, end / 1000)
        raws = self._request_and_wait(self.push_socket, "BARS", request)
        return self._parse_bars(raws)

    def _parse_bars(self, data):
        raws = data.split(";")

        # building status
        if raws[-1] == "building":
            raws.pop()
            building = True
        else:
            building = False

        # parsing
        bars = []
        for raw in raws:
            if not raw:
                continue

            bar = self._parse_bar(raw)
            bars.append(bar)
        return bars, building

    def _parse_bar(self, raw):
        bar = raw.split("|")
        bar[0] = float(bar[0]) * 1000
        for i in range(1, len(bar)):
            bar[i] = float(bar[i])
        return bar

    # symbols
    def get_markets(self):
        data = self._request_and_wait(self.push_socket, "MARKETS")
        return self._parse_markets(data)

    def _parse_markets(self, data):
        raws = data.split(";")
        markets = []
        for raw in raws:
            markets.append(self._parse_market(raw))

        self.markets = {m["id"]: m for m in markets}
        return markets

    _market_format = dict(
        point=float,
        digits=float,
        minlot=float,
        lotstep=float,
        maxlot=float,
        lotsize=float,
        ticksize=float,
        tickvalue=float,
    )

    def _parse_market(self, raw):
        market = self._parse_data_dict(raw, self._market_format)
        market["id"] = market["symbol"]
        return market

    # quote
    def get_quotes(self, symbols=[]):
        quotes = self._request_and_wait(self.push_socket, "QUOTES")
        quotes = self._parse_quotes(quotes)
        if not symbols:
            return quotes

        results = []
        for quote in quotes:
            if quote["symbol"] in symbols:
                results.append(quote)
        return results

    def _parse_quotes(self, data):
        raws = data.split(";")
        quotes = []
        for raw in raws:
            quotes.append(self._parse_quote(raw))
        return quotes

    _quote_format = dict(
        open=float,
        high=float,
        low=float,
        close=float,
        volume=float,
        bid=float,
        ask=float,
        last=float,
        spread=float,
        prev_close=float,
        change=float,
        change_percent=float,
    )

    def _parse_quote(self, raw):
        quote = self._parse_data_dict(raw, self._quote_format)
        return quote

    def subscribe_quotes(self, symbol):
        data = self._request_and_wait(self.push_socket, "SUB_QUOTES", symbol)
        return True

    def unsubscribe_quotes(self, symbol):
        data = self._request_and_wait(self.push_socket, "UNSUB_QUOTES", symbol)
        return True

    # ACCOUNT
    # account
    def get_account(self):
        data = self._request_and_wait(self.push_socket, "ACCOUNT")
        return self._parse_account(data)

    _account_format = dict(
        id=int,
        deposit=float,
        margin=float,
        leverage=int,
        gmtoffset=int,
    )

    def _parse_account(self, raw):
        return self._parse_data_dict(raw, self._account_format)

    # fund
    def get_fund(self):
        data = self._request_and_wait(self.push_socket, "FUND")
        return self._parse_fund(data)

    _fund_format = dict(
        balance=float,
        equity=float,
    )

    def _parse_fund(self, raw):
        fund = self._parse_data_dict(raw, self._fund_format)
        return fund

    # trades
    def get_trades(self, symbol=""):
        data = self._request_and_wait(self.push_socket, "TRADES", symbol)
        return self._parse_trades(data)

    def modify_trade(self, ticket, sl=0, tp=0):
        request = f"{ticket};{sl or 0};{tp or 0}"
        self._request_and_wait(self.push_socket, "MODIFY_TRADE", request)
        return True

    def close_trade(self, ticket):
        self._request_and_wait(self.push_socket, "CLOSE_TRADE", ticket)
        return True

    def _parse_trades(self, data):
        raws = data.split(";")
        trades = []
        for raw in raws:
            if not raw:
                continue

            trade = self._parse_trade(raw)
            trades.append(trade)
        return trades

    _trade_format = dict(
        ticket=int,
        open_price=float,
        open_time=float,
        lots=float,
        sl=float,
        tp=float,
        pnl=float,
        swap=float,
    )

    def _parse_trade(self, raw):
        trade = self._parse_data_dict(raw, self._trade_format)
        trade["open_time"] = trade["open_time"] * 1000
        return trade

    # deals
    def get_deals(self, symbol="", fromdate=0):
        request = "{};{}".format(symbol, fromdate)
        data = self._request_and_wait(self.push_socket, "DEALS", request)
        return self._parse_deals(data)

    def _parse_deals(self, data):
        raws = data.split(";")
        deals = []
        for raw in raws:
            if not raw:
                continue
            deal = self._parse_deal(raw)
            if deal:
                deals.append(deal)
        return deals

    _deal_format = dict(
        ticket=int,
        order=int,
        position=int,
        price=float,
        time=float,
        lots=float,
        sl=float,
        tp=float,
        swap=float,
        pnl=float,
        commission=float,
    )

    def _parse_deal(self, raw):
        deal = self._parse_data_dict(raw, self._deal_format)
        if deal["type"] == "DEAL_TYPE_BALANCE":
            return None

        deal["time"] = deal["time"] * 1000
        return deal

    # orders
    def get_open_orders(self):
        data = self._request_and_wait(self.push_socket, "ORDERS")
        return self._parse_orders(data)

    def _parse_orders(self, data):
        raws = data.split(";")
        orders = []
        for raw in raws:
            if not raw:
                continue

            order = self._parse_order(raw)
            orders.append(order)
        return orders

    _order_format = dict(
        ticket=int,
        position=int,
        open_price=float,
        open_time=float,
        close_time=float,
        lots=float,
        sl=float,
        tp=float,
        expiration=float,
    )

    def _parse_order(self, raw):
        order = self._parse_data_dict(raw, self._order_format)
        order["open_time"] = order["open_time"] * 1000
        order["close_time"] = order["close_time"] * 1000
        order["expiration"] = order["expiration"] * 1000
        return order

    def open_order(self, symbol, type, lots, price, sl=0, tp=0, comment=""):
        request = f"{symbol};{type};{lots};{price or 0};{sl or 0};{tp or 0};{comment}"
        ticket = self._request_and_wait(self.push_socket, "OPEN_ORDER", request)
        return int(ticket)

    def modify_order(self, ticket, price, sl=0, tp=0, expiration=0):
        request = f"{ticket};{price or 0};{sl or 0};{tp or 0};{expiration or 0}"
        data = self._request_and_wait(self.push_socket, "MODIFY_ORDER", request)
        return True

    def cancel_order(self, ticket):
        self._request_and_wait(self.push_socket, "CANCEL_ORDER", ticket)
        return True

    # helpers
    def _parse_data_dict(self, data, format):
        raws = data.split("|")
        result = dict()
        for raw in raws:
            key, val = raw.split("=", 1)
            type = format.get(key, str)
            try:
                result[key] = type(val)
            except:
                raise RuntimeError(
                    f"Cannot parse value {val} by key {key}, "
                    f"type {type} for data {data}"
                )
        return result
