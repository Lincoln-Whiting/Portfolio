import requests
import json
import time
import os
from datetime import datetime, timedelta
from itertools import permutations
import networkx as nx
import matplotlib.pyplot as plt

# Create lists for JSON data
crypto = ['ripple', 'cardano', 'bitcoin-cash', 'eos', 'litecoin', 'ethereum', 'bitcoin']
symbol = ['xrp', 'ada', 'bch', 'eos', 'ltc', 'eth', 'btc']

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
# Add edges to the graph 
for c1, s1 in zip(crypto, symbol):
    for c2, s2 in zip(crypto, symbol):
        if c1 is not c2:
            try:
                rate = data[c1][s2]
                g.add_weighted_edges_from([(s1, s2, rate)])
            except KeyError:
                continue

# def function to calculate weight paths 
def calculate_path_weight(path):
    weight = 1.0
    for i in range(len(path) - 1):
        weight *= g[path[i]][path[i + 1]]['weight']
    return weight

# Function to find arbitrage opportunities
def find_arbitrage_opportunities():
    arbitrage_opportunities = []
    for s1 in symbol:
        for s2 in symbol:
            if s1 is not s2:
                paths_to = (nx.all_simple_paths(g, s1, s2))
                paths_from = (nx.all_simple_paths(g, s2, s1))
                for path_to in paths_to:
                    weight_to = calculate_path_weight(path_to)
                    for path_from in paths_from:
                        weight_from = calculate_path_weight(path_from)
                        factor = weight_to * weight_from
                        if factor is not 1.0:
                            arbitrage_opportunities.append((path_to, path_from, factor))
    return arbitrage_opportunities

# Call find_arbitrage_opportunities and print 
arbitrage_opportunities = find_arbitrage_opportunities()
for path_to, path_from, factor in arbitrage_opportunities:
    print(f"Path to– {path_to}, Path from– {path_from},\nFactor– {factor}")

# Find smallest and greatest path factor
if arbitrage_opportunities:
    smallest_factor = min(arbitrage_opportunities, key=lambda x: x[2]) 
    greatest_factor = max(arbitrage_opportunities, key=lambda x: x[2])
    print(f"\nSmallest Paths weight factor– {smallest_factor[2]}")
    print(f"Paths: {smallest_factor[0]} {smallest_factor[1]}")
    print(f"\nGreatest Paths weight factor– {greatest_factor[2]}")
    print(f"Paths– {greatest_factor[0]} {greatest_factor[1]}")
else:
    print("No arbitrage opportunities found.")

