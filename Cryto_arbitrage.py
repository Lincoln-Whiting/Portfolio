import requests
import json
import time
import os
from datetime import datetime
import networkx as nx
import csv
import alpaca_trade_api as tradeapi

# Create lists for JSON data
crypto = ['maker', 'polkadot', 'bitcoin-cash', 'dogecoin', 'litecoin', 'ethereum', 'bitcoin', 'aave', 'tether', 'chainlink', 'tezos']
symbol = ['mkr', 'dot', 'bch', 'doge', 'ltc', 'eth', 'btc', 'aave', 'usdt', 'link', 'xtz']

# Create graph and initialize 
g = nx.DiGraph()
edges = []

url1 = "https://api.coingecko.com/api/v3/simple/price?ids="
url2 = "&vs_currencies="

# Join crypto names for .get() 
ids = ','.join(crypto)
symbols = ','.join(symbol)

# Fetch exchange rates from coinGecko API
response = requests.get(f"{url1}{ids}{url2}{symbols}")
data = response.json()

# Set up alpaca api
api_key = "PK0BBEWWFXHUR8JO23FZ"
api_secret = "Qll3dPMhVcM5ebvimSgOp3K3KY9QhFuRw5Wk36tw"
base_url = "https://paper-api.alpaca.markets"
api = tradeapi.REST(api_key, api_secret, base_url, api_version='v2')
account = api.get_account() #creat account variable
print(account)

# Add edges to the graph using nested for loop
for c1, s1 in zip(crypto, symbol):
    for c2, s2 in zip(crypto, symbol):
        if c1 != c2:
            try:
                rate = data[c1][s2]
                g.add_weighted_edges_from([(s1, s2, rate)]) #calculate rate & add to graph edges
            except KeyError:
                continue

# Function to calculate weight paths 
def calculate_path_weight(path):
    weight = 1.0
    for i in range(len(path) - 1):
        weight *= g[path[i]][path[i + 1]]['weight']
    return weight

# Function to find arbitrage opportunities, iterate through all paths using nested loops
def find_arbitrage_opportunities():
    arbitrage_opportunities = []
    for s1 in symbol:
        for s2 in symbol:
            if s1 != s2:
                paths_to = (nx.all_simple_paths(g, s1, s2))
                paths_from = (nx.all_simple_paths(g, s2, s1))
                for path_to in paths_to:
                    weight_to = calculate_path_weight(path_to)
                    for path_from in paths_from:
                        weight_from = calculate_path_weight(path_from)
                        factor = weight_to * weight_from
                        if factor != 1.0:
                            arbitrage_opportunities.append((path_to, path_from, factor))
    return arbitrage_opportunities #return all arbitrage opportunities

# Function to save all arbitrage paths to CSV
def save_to_csv(arbitrage_opportunities):
    if not os.path.exists("/Users/lincolnwhiting/Desktop/Fall 2024/DATA 5500/data5500_hw/final_project/data"):
        os.makedirs("/Users/lincolnwhiting/Desktop/Fall 2024/DATA 5500/data5500_hw/final_project/data")

    timestamp = datetime.now().strftime("%Y.%m.%d:%H.%M") #add timestamp to file
    filename = f"/Users/lincolnwhiting/Desktop/Fall 2024/DATA 5500/data5500_hw/final_project/data/arbitrage_paths_{timestamp}.csv"
#write to csv
    with open(filename, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Path To', 'Path From', 'Factor'])
        for path_to, path_from, factor in arbitrage_opportunities:
            writer.writerow([path_to, path_from, factor])

# Paper trade function to buy/sell best found arbitrage opportunity
def paper_trade():
    executed_trades = [] #initialize executed trades for json
    arbitrage_opportunities = find_arbitrage_opportunities()

    if arbitrage_opportunities:
        # Get the arbitrage opportunity with the highest factor
        greatest_factor = max(arbitrage_opportunities, key=lambda x: x[2])
        path_to, path_from, factor = greatest_factor

        if factor > 1:  # Only trade if MAX arbitrage factor is profitable
            try:
                # Buy and sell coins in path_to list, but & sell back with USD
                for i in range(len(path_to) - 1):
                    # Buy the first asset with USD
                    buy_order = api.submit_order(
                        symbol=f'{path_to[i].upper()}USD',  # Buy the asset with USD
                        notional=1000,  # 
                        side='buy',
                        time_in_force='gtc'
                    )
                    print(f"Buy order for {path_to[i]} with USD.") #print buy
                    
                    # Sell coin back USD
                    sell_order = api.submit_order(
                        symbol=f'{path_to[i].upper()}USD',  
                        notional=1000*.9,  # times by .9 to account for market changes & fee
                        side='sell',
                        time_in_force='gtc'
                    )
                    print(f"Sell order for {path_to[i]} to USD.") #print sell
                    
                # execute trades along the 'path_from' list, buy with USD and sell back to USD
                for i in range(len(path_from) - 1): #iterate through path_from list
                    buy_order = api.submit_order(
                        symbol=f'{path_from[i].upper()}USD', 
                        notional=1000,  # Adjusted quantity (100 USD worth of asset)
                        side='buy',
                        time_in_force='gtc'
                    )
                    print(f"Buy order for {path_from[i]} with USD.") #print buy
                    #sell coin back for USD
                    sell_order = api.submit_order(
                        symbol=f'{path_from[i].upper()}USD',  
                        notional=1000 *.9,  # times by .9 to account for market changes & fee
                        side='sell',
                        time_in_force='gtc'
                    )
                    print(f"Sell order for {path_from[i]} to USD.") #print sell
                
                # Append the trade in the required format
                executed_trades.append({
                    "path_to": path_to,
                    "path_from": path_from,
                    "factor": factor
                })

            except Exception as e:
                print(f"An error occurred: {e}")
        else: #print if arbitrage factor is too low (less than 1)
            print("Arbitrage factor too low for a profitable trade.")
    return executed_trades

    # Load data and account balance into results.json
def save_alpaca_json(executed_trades, account):
    file_path = "/Users/lincolnwhiting/Desktop/Fall 2024/DATA 5500/data5500_hw/final_project/results.json"
    
    # call alpaca account info
    account_info = {
        "cash": account.cash,
        "portfolio_value": account.portfolio_value,
    }

    # format the above trades
    formatted_trades = [{"path_to": trade["path_to"], "path_from": trade["path_from"], "factor": trade["factor"]} for trade in executed_trades]

    # format account data for .json
    data = {
        "executed_trades": formatted_trades,
        "alpaca_account_info": account_info
    }
    
    # Try writing the data to the file
    try:
        with open(file_path, 'w') as json_file:
            json.dump(data, json_file, indent=2)
            print(f"Data successfully written to {file_path}")
    except Exception as e:
        print(f"Error writing to file: {e}")

arbitrage_opportunities = find_arbitrage_opportunities()
for path_to, path_from, factor in arbitrage_opportunities:
    print(f"Path to– {path_to}, Path from– {path_from},\nFactor– {factor}")

executed_trades = paper_trade()  # save & call paper_trade Execute the trades and store them in the variable
save_alpaca_json(executed_trades, account)  
else:
    print("No arbitrage opportunities found.")
