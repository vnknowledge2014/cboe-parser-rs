use crate::message::*;
use std::collections::{BTreeMap, HashMap};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OrderBookEntry {
    pub order_id: OrderId,
    pub price: Price,
    pub quantity: u32,
    pub side: Side,
    pub pid: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderBook {
    symbol: String,
    orders: HashMap<OrderId, OrderBookEntry>,
    bids: BTreeMap<u64, Vec<OrderId>>,
    asks: BTreeMap<u64, Vec<OrderId>>,
    trading_status: TradingStatus,
}

impl OrderBook {
    pub fn new(symbol: String) -> Self {
        Self {
            symbol,
            orders: HashMap::new(),
            bids: BTreeMap::new(),
            asks: BTreeMap::new(),
            trading_status: TradingStatus::Closed,
        }
    }
    
    pub fn apply_message(&mut self, message: &PitchMessage) {
        match message {
            PitchMessage::TradingStatus { symbol, trading_status, .. } => {
                if symbol == &self.symbol {
                    self.trading_status = *trading_status;
                }
            },
            PitchMessage::AddOrder { order_id, side, quantity, symbol, price, pid, timestamp } => {
                if symbol == &self.symbol && *quantity > 0 {
                    let entry = OrderBookEntry {
                        order_id: *order_id,
                        price: *price,
                        quantity: *quantity,
                        side: *side,
                        pid: pid.clone(),
                        timestamp: *timestamp,
                    };
                    
                    self.orders.insert(*order_id, entry);
                    
                    match side {
                        Side::Buy => {
                            self.bids.entry(price.0).or_default().push(*order_id);
                        },
                        Side::Sell => {
                            self.asks.entry(price.0).or_default().push(*order_id);
                        }
                    }
                }
            },
            PitchMessage::OrderExecuted { order_id, executed_quantity, .. } => {
                if let Some(order) = self.orders.get_mut(order_id) {
                    if order.quantity >= *executed_quantity {
                        order.quantity -= executed_quantity;
                        if order.quantity == 0 {
                            self.remove_order(*order_id);
                        }
                    }
                }
            },
            PitchMessage::DeleteOrder { order_id, .. } => {
                self.remove_order(*order_id);
            },
            _ => {
                // Other messages
            }
        }
    }
    
    fn remove_order(&mut self, order_id: OrderId) {
        if let Some(order) = self.orders.remove(&order_id) {
            match order.side {
                Side::Buy => {
                    if let Some(orders) = self.bids.get_mut(&order.price.0) {
                        orders.retain(|&id| id != order_id);
                        if orders.is_empty() {
                            self.bids.remove(&order.price.0);
                        }
                    }
                },
                Side::Sell => {
                    if let Some(orders) = self.asks.get_mut(&order.price.0) {
                        orders.retain(|&id| id != order_id);
                        if orders.is_empty() {
                            self.asks.remove(&order.price.0);
                        }
                    }
                }
            }
        }
    }
    
    pub fn best_bid(&self) -> Option<Price> {
        self.bids.keys().last().map(|&price| Price(price))
    }
    
    pub fn best_ask(&self) -> Option<Price> {
        self.asks.keys().next().map(|&price| Price(price))
    }
    
    pub fn spread(&self) -> Option<Price> {
        match (self.best_bid(), self.best_ask()) {
            (Some(bid), Some(ask)) => {
                if ask.0 >= bid.0 {
                    Some(Price(ask.0 - bid.0))
                } else {
                    None
                }
            },
            _ => None,
        }
    }
    
    pub fn get_level_info(&self, levels: usize) -> (Vec<(Price, u32)>, Vec<(Price, u32)>) {
        let bids: Vec<(Price, u32)> = self.bids
            .iter()
            .rev()
            .take(levels)
            .map(|(&price_raw, order_ids)| {
                let total_qty = order_ids.iter()
                    .filter_map(|&id| self.orders.get(&id))
                    .map(|order| order.quantity)
                    .sum();
                (Price(price_raw), total_qty)
            })
            .collect();
            
        let asks: Vec<(Price, u32)> = self.asks
            .iter()
            .take(levels)
            .map(|(&price_raw, order_ids)| {
                let total_qty = order_ids.iter()
                    .filter_map(|&id| self.orders.get(&id))
                    .map(|order| order.quantity)
                    .sum();
                (Price(price_raw), total_qty)
            })
            .collect();
            
        (bids, asks)
    }
    
    pub fn symbol(&self) -> &str {
        &self.symbol
    }
    
    pub fn trading_status(&self) -> TradingStatus {
        self.trading_status
    }
    
    pub fn order_count(&self) -> usize {
        self.orders.len()
    }
    
    pub fn total_bid_quantity(&self) -> u32 {
        self.orders.values()
            .filter(|order| order.side == Side::Buy)
            .map(|order| order.quantity)
            .sum()
    }
    
    pub fn total_ask_quantity(&self) -> u32 {
        self.orders.values()
            .filter(|order| order.side == Side::Sell)
            .map(|order| order.quantity)
            .sum()
    }
}
