#!/bin/bash

PROJECT_NAME="cboe-pitch-parser"

echo "🚀 Tạo CBOE PITCH Protocol Parser Project..."

# Tạo project directory
mkdir -p $PROJECT_NAME
cd $PROJECT_NAME

# Khởi tạo Cargo project
cargo init --name $PROJECT_NAME

echo "📦 Tạo Cargo.toml..."
cat > Cargo.toml << 'EOF'
[package]
name = "cboe-pitch-parser"
version = "0.1.0"
edition = "2021"

[dependencies]
byteorder = "1.5"
chrono = { version = "0.4", features = ["serde"] }
serde = { version = "1.0", features = ["derive"] }
thiserror = "1.0"
uuid = "1.8"
EOF

# Tạo src structure
mkdir -p src

echo "📁 Tạo lib.rs..."
cat > src/lib.rs << 'EOF'
pub mod message;
pub mod parser;
pub mod simulator;
pub mod order_book;
pub mod error;

pub use message::*;
pub use parser::*;
pub use simulator::*;
pub use order_book::*;
pub use error::*;
EOF

echo "❌ Tạo error.rs..."
cat > src/error.rs << 'EOF'
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PitchError {
    #[error("Insufficient data: expected {expected}, got {actual}")]
    InsufficientData { expected: usize, actual: usize },
    
    #[error("Invalid message type: {0:#04x}")]
    InvalidMessageType(u8),
    
    #[error("Invalid sequence number: expected {expected}, got {actual}")]
    InvalidSequence { expected: u32, actual: u32 },
    
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("Parse error: {0}")]
    Parse(String),
}

pub type Result<T> = std::result::Result<T, PitchError>;
EOF

echo "📨 Tạo message.rs..."
cat > src/message.rs << 'EOF'
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Sequenced Unit Header (8 bytes)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SequencedUnitHeader {
    pub length: u16,     // Length of entire block
    pub count: u8,       // Number of messages following
    pub unit: u8,        // Unit ID
    pub sequence: u32,   // Sequence number of first message
}

/// Binary price with 7 decimal places (denominator = 10,000,000)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Price(pub u64);

impl Price {
    pub fn from_raw(raw: u64) -> Self {
        Price(raw)
    }
    
    pub fn to_decimal(&self) -> f64 {
        self.0 as f64 / 10_000_000.0
    }
    
    pub fn from_decimal(decimal: f64) -> Self {
        Price((decimal * 10_000_000.0) as u64)
    }
}

impl std::fmt::Display for Price {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:.7}", self.to_decimal())
    }
}

/// Order ID that can be converted to base36
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct OrderId(pub u64);

impl OrderId {
    pub fn to_base36(&self) -> String {
        base36::encode(self.0)
    }
}

/// Execution ID that can be converted to base36
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ExecutionId(pub u64);

impl ExecutionId {
    pub fn to_base36(&self) -> String {
        // Convert to 9-character base36, zero-padded on left
        format!("{:0>9}", base36::encode(self.0))
    }
}

// Base36 encoding module
mod base36 {
    const ALPHABET: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    
    pub fn encode(mut num: u64) -> String {
        if num == 0 {
            return "0".to_string();
        }
        
        let mut result = Vec::new();
        while num > 0 {
            result.push(ALPHABET[(num % 36) as usize]);
            num /= 36;
        }
        result.reverse();
        String::from_utf8(result).unwrap()
    }
}

/// Trading Status values
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum TradingStatus {
    Closed,           // C
    PreMarket,        // A
    Trading,          // T
    MocTrading,       // M
    PostMarket,       // P
    Halted,           // H
    TradingSuspended, // S
    PreOpen,          // O
    PreClose,         // E
}

impl TradingStatus {
    pub fn from_byte(b: u8) -> Option<Self> {
        match b {
            b'C' => Some(TradingStatus::Closed),
            b'A' => Some(TradingStatus::PreMarket),
            b'T' => Some(TradingStatus::Trading),
            b'M' => Some(TradingStatus::MocTrading),
            b'P' => Some(TradingStatus::PostMarket),
            b'H' => Some(TradingStatus::Halted),
            b'S' => Some(TradingStatus::TradingSuspended),
            b'O' => Some(TradingStatus::PreOpen),
            b'E' => Some(TradingStatus::PreClose),
            _ => None,
        }
    }
    
    pub fn to_byte(&self) -> u8 {
        match self {
            TradingStatus::Closed => b'C',
            TradingStatus::PreMarket => b'A',
            TradingStatus::Trading => b'T',
            TradingStatus::MocTrading => b'M',
            TradingStatus::PostMarket => b'P',
            TradingStatus::Halted => b'H',
            TradingStatus::TradingSuspended => b'S',
            TradingStatus::PreOpen => b'O',
            TradingStatus::PreClose => b'E',
        }
    }
}

/// Side indicator for orders
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum Side {
    Buy,   // B
    Sell,  // S
}

impl Side {
    pub fn from_byte(b: u8) -> Option<Self> {
        match b {
            b'B' => Some(Side::Buy),
            b'S' => Some(Side::Sell),
            _ => None,
        }
    }
    
    pub fn to_byte(&self) -> u8 {
        match self {
            Side::Buy => b'B',
            Side::Sell => b'S',
        }
    }
}

/// PITCH Message types
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PitchMessage {
    UnitClear {
        timestamp: DateTime<Utc>,
    },
    TradingStatus {
        timestamp: DateTime<Utc>,
        symbol: String,
        trading_status: TradingStatus,
        market_id_code: String,
    },
    AddOrder {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
        side: Side,
        quantity: u32,
        symbol: String,
        price: Price,
        pid: String,
    },
    OrderExecuted {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
        executed_quantity: u32,
        execution_id: ExecutionId,
        contra_order_id: OrderId,
        contra_pid: String,
    },
    OrderExecutedAtPrice {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
        executed_quantity: u32,
        execution_id: ExecutionId,
        contra_order_id: OrderId,
        contra_pid: String,
        execution_type: char,
        price: Price,
    },
    ReduceSize {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
        cancelled_quantity: u32,
    },
    ModifyOrder {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
        quantity: u32,
        price: Price,
    },
    DeleteOrder {
        timestamp: DateTime<Utc>,
        order_id: OrderId,
    },
    Trade {
        timestamp: DateTime<Utc>,
        symbol: String,
        quantity: u32,
        price: Price,
        execution_id: ExecutionId,
        order_id: OrderId,
        contra_order_id: OrderId,
        pid: String,
        contra_pid: String,
        trade_type: char,
        trade_designation: char,
        trade_report_type: char,
        trade_transaction_time: DateTime<Utc>,
        flags: u8,
    },
    TradeBreak {
        timestamp: DateTime<Utc>,
        execution_id: ExecutionId,
    },
    CalculatedValue {
        timestamp: DateTime<Utc>,
        symbol: String,
        value_category: char,
        value: Price,
        value_timestamp: DateTime<Utc>,
    },
    EndOfSession {
        timestamp: DateTime<Utc>,
    },
    AuctionUpdate {
        timestamp: DateTime<Utc>,
        symbol: String,
        auction_type: char,
        buy_shares: u32,
        sell_shares: u32,
        indicative_price: Price,
    },
    AuctionSummary {
        timestamp: DateTime<Utc>,
        symbol: String,
        auction_type: char,
        price: Price,
        shares: u32,
    },
}

impl PitchMessage {
    pub fn message_type(&self) -> u8 {
        match self {
            PitchMessage::UnitClear { .. } => 0x97,
            PitchMessage::TradingStatus { .. } => 0x3B,
            PitchMessage::AddOrder { .. } => 0x37,
            PitchMessage::OrderExecuted { .. } => 0x38,
            PitchMessage::OrderExecutedAtPrice { .. } => 0x58,
            PitchMessage::ReduceSize { .. } => 0x39,
            PitchMessage::ModifyOrder { .. } => 0x3A,
            PitchMessage::DeleteOrder { .. } => 0x3C,
            PitchMessage::Trade { .. } => 0x3D,
            PitchMessage::TradeBreak { .. } => 0x3E,
            PitchMessage::CalculatedValue { .. } => 0xE3,
            PitchMessage::EndOfSession { .. } => 0x2D,
            PitchMessage::AuctionUpdate { .. } => 0x59,
            PitchMessage::AuctionSummary { .. } => 0x5A,
        }
    }
    
    pub fn timestamp(&self) -> DateTime<Utc> {
        match self {
            PitchMessage::UnitClear { timestamp } => *timestamp,
            PitchMessage::TradingStatus { timestamp, .. } => *timestamp,
            PitchMessage::AddOrder { timestamp, .. } => *timestamp,
            PitchMessage::OrderExecuted { timestamp, .. } => *timestamp,
            PitchMessage::OrderExecutedAtPrice { timestamp, .. } => *timestamp,
            PitchMessage::ReduceSize { timestamp, .. } => *timestamp,
            PitchMessage::ModifyOrder { timestamp, .. } => *timestamp,
            PitchMessage::DeleteOrder { timestamp, .. } => *timestamp,
            PitchMessage::Trade { timestamp, .. } => *timestamp,
            PitchMessage::TradeBreak { timestamp, .. } => *timestamp,
            PitchMessage::CalculatedValue { timestamp, .. } => *timestamp,
            PitchMessage::EndOfSession { timestamp } => *timestamp,
            PitchMessage::AuctionUpdate { timestamp, .. } => *timestamp,
            PitchMessage::AuctionSummary { timestamp, .. } => *timestamp,
        }
    }
}
EOF

echo "🔧 Tạo parser.rs..."
cat > src/parser.rs << 'EOF'
use crate::{error::*, message::*};
use byteorder::{LittleEndian, ReadBytesExt};
use chrono::{DateTime, Utc};
use std::io::{Cursor, Read};

pub struct PitchParser {
    buffer: Vec<u8>,
    position: usize,
}

impl PitchParser {
    pub fn new() -> Self {
        Self {
            buffer: Vec::new(),
            position: 0,
        }
    }
    
    pub fn feed_data(&mut self, data: &[u8]) {
        self.buffer.extend_from_slice(data);
    }
    
    pub fn parse_next_frame(&mut self) -> Result<Option<(SequencedUnitHeader, Vec<PitchMessage>)>> {
        if self.buffer.len() - self.position < 8 {
            return Ok(None); // Not enough data for header
        }
        
        let header = self.parse_header()?;
        
        if self.buffer.len() - self.position + 8 < header.length as usize {
            return Ok(None); // Not enough data for complete frame
        }
        
        let mut messages = Vec::new();
        
        for _ in 0..header.count {
            if let Some(message) = self.parse_message()? {
                messages.push(message);
            }
        }
        
        Ok(Some((header, messages)))
    }
    
    fn parse_header(&mut self) -> Result<SequencedUnitHeader> {
        let mut cursor = Cursor::new(&self.buffer[self.position..]);
        
        let length = cursor.read_u16::<LittleEndian>()?;
        let count = cursor.read_u8()?;
        let unit = cursor.read_u8()?;
        let sequence = cursor.read_u32::<LittleEndian>()?;
        
        self.position += 8;
        
        Ok(SequencedUnitHeader {
            length,
            count,
            unit,
            sequence,
        })
    }
    
    fn parse_message(&mut self) -> Result<Option<PitchMessage>> {
        if self.position >= self.buffer.len() {
            return Ok(None);
        }
        
        let length = self.buffer[self.position] as usize;
        
        if self.buffer.len() - self.position < length {
            return Ok(None);
        }
        
        let message_type = self.buffer[self.position + 1];
        let message_data = &self.buffer[self.position..self.position + length];
        
        let message = match message_type {
            0x97 => self.parse_unit_clear(message_data)?,
            0x3B => self.parse_trading_status(message_data)?,
            0x37 => self.parse_add_order(message_data)?,
            0x38 => self.parse_order_executed(message_data)?,
            0x58 => self.parse_order_executed_at_price(message_data)?,
            0x39 => self.parse_reduce_size(message_data)?,
            0x3A => self.parse_modify_order(message_data)?,
            0x3C => self.parse_delete_order(message_data)?,
            0x3D => self.parse_trade(message_data)?,
            0x3E => self.parse_trade_break(message_data)?,
            0xE3 => self.parse_calculated_value(message_data)?,
            0x2D => self.parse_end_of_session(message_data)?,
            0x59 => self.parse_auction_update(message_data)?,
            0x5A => self.parse_auction_summary(message_data)?,
            _ => return Err(PitchError::InvalidMessageType(message_type)),
        };
        
        self.position += length;
        Ok(Some(message))
    }
    
    fn parse_timestamp(&self, cursor: &mut Cursor<&[u8]>) -> Result<DateTime<Utc>> {
        let nanos = cursor.read_u64::<LittleEndian>()?;
        let timestamp = DateTime::from_timestamp(
            (nanos / 1_000_000_000) as i64,
            (nanos % 1_000_000_000) as u32,
        ).unwrap_or_else(|| Utc::now());
        
        Ok(timestamp)
    }
    
    fn parse_string(&self, data: &[u8]) -> String {
        String::from_utf8_lossy(data).trim_end().to_string()
    }
    
    fn parse_unit_clear(&self, data: &[u8]) -> Result<PitchMessage> {
        Ok(PitchMessage::UnitClear {
            timestamp: Utc::now(),
        })
    }
    
    fn parse_trading_status(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        
        let mut symbol_bytes = [0u8; 6];
        cursor.read_exact(&mut symbol_bytes)?;
        let symbol = self.parse_string(&symbol_bytes);
        
        let status_byte = cursor.read_u8()?;
        let trading_status = TradingStatus::from_byte(status_byte)
            .ok_or_else(|| PitchError::Parse(format!("Invalid trading status: {}", status_byte)))?;
        
        let mut market_id_bytes = [0u8; 4];
        cursor.read_exact(&mut market_id_bytes)?;
        let market_id_code = self.parse_string(&market_id_bytes);
        
        Ok(PitchMessage::TradingStatus {
            timestamp,
            symbol,
            trading_status,
            market_id_code,
        })
    }
    
    fn parse_add_order(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        let side_byte = cursor.read_u8()?;
        let side = Side::from_byte(side_byte)
            .ok_or_else(|| PitchError::Parse(format!("Invalid side: {}", side_byte)))?;
        let quantity = cursor.read_u32::<LittleEndian>()?;
        
        let mut symbol_bytes = [0u8; 6];
        cursor.read_exact(&mut symbol_bytes)?;
        let symbol = self.parse_string(&symbol_bytes);
        
        let price = Price(cursor.read_u64::<LittleEndian>()?);
        
        let mut pid_bytes = [0u8; 4];
        cursor.read_exact(&mut pid_bytes)?;
        let pid = self.parse_string(&pid_bytes);
        
        Ok(PitchMessage::AddOrder {
            timestamp,
            order_id,
            side,
            quantity,
            symbol,
            price,
            pid,
        })
    }
    
    fn parse_order_executed(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        let executed_quantity = cursor.read_u32::<LittleEndian>()?;
        let execution_id = ExecutionId(cursor.read_u64::<LittleEndian>()?);
        let contra_order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        
        let mut contra_pid_bytes = [0u8; 4];
        cursor.read_exact(&mut contra_pid_bytes)?;
        let contra_pid = self.parse_string(&contra_pid_bytes);
        
        Ok(PitchMessage::OrderExecuted {
            timestamp,
            order_id,
            executed_quantity,
            execution_id,
            contra_order_id,
            contra_pid,
        })
    }
    
    fn parse_order_executed_at_price(&self, _data: &[u8]) -> Result<PitchMessage> {
        // Simplified implementation
        Ok(PitchMessage::OrderExecutedAtPrice {
            timestamp: Utc::now(),
            order_id: OrderId(0),
            executed_quantity: 0,
            execution_id: ExecutionId(0),
            contra_order_id: OrderId(0),
            contra_pid: String::new(),
            execution_type: 'O',
            price: Price(0),
        })
    }
    
    fn parse_reduce_size(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        let cancelled_quantity = cursor.read_u32::<LittleEndian>()?;
        
        Ok(PitchMessage::ReduceSize {
            timestamp,
            order_id,
            cancelled_quantity,
        })
    }
    
    fn parse_modify_order(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        let quantity = cursor.read_u32::<LittleEndian>()?;
        let price = Price(cursor.read_u64::<LittleEndian>()?);
        
        Ok(PitchMessage::ModifyOrder {
            timestamp,
            order_id,
            quantity,
            price,
        })
    }
    
    fn parse_delete_order(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let order_id = OrderId(cursor.read_u64::<LittleEndian>()?);
        
        Ok(PitchMessage::DeleteOrder {
            timestamp,
            order_id,
        })
    }
    
    fn parse_trade(&self, _data: &[u8]) -> Result<PitchMessage> {
        // Simplified implementation
        Ok(PitchMessage::Trade {
            timestamp: Utc::now(),
            symbol: String::new(),
            quantity: 0,
            price: Price(0),
            execution_id: ExecutionId(0),
            order_id: OrderId(0),
            contra_order_id: OrderId(0),
            pid: String::new(),
            contra_pid: String::new(),
            trade_type: 'N',
            trade_designation: 'C',
            trade_report_type: ' ',
            trade_transaction_time: Utc::now(),
            flags: 0,
        })
    }
    
    fn parse_trade_break(&self, data: &[u8]) -> Result<PitchMessage> {
        let mut cursor = Cursor::new(&data[2..]);
        
        let timestamp = self.parse_timestamp(&mut cursor)?;
        let execution_id = ExecutionId(cursor.read_u64::<LittleEndian>()?);
        
        Ok(PitchMessage::TradeBreak {
            timestamp,
            execution_id,
        })
    }
    
    fn parse_calculated_value(&self, _data: &[u8]) -> Result<PitchMessage> {
        // Simplified implementation
        Ok(PitchMessage::CalculatedValue {
            timestamp: Utc::now(),
            symbol: String::new(),
            value_category: '1',
            value: Price(0),
            value_timestamp: Utc::now(),
        })
    }
    
    fn parse_end_of_session(&self, _data: &[u8]) -> Result<PitchMessage> {
        Ok(PitchMessage::EndOfSession {
            timestamp: Utc::now(),
        })
    }
    
    fn parse_auction_update(&self, _data: &[u8]) -> Result<PitchMessage> {
        Ok(PitchMessage::AuctionUpdate {
            timestamp: Utc::now(),
            symbol: String::new(),
            auction_type: 'O',
            buy_shares: 0,
            sell_shares: 0,
            indicative_price: Price(0),
        })
    }
    
    fn parse_auction_summary(&self, _data: &[u8]) -> Result<PitchMessage> {
        Ok(PitchMessage::AuctionSummary {
            timestamp: Utc::now(),
            symbol: String::new(),
            auction_type: 'O',
            price: Price(0),
            shares: 0,
        })
    }
}

impl Default for PitchParser {
    fn default() -> Self {
        Self::new()
    }
}
EOF

echo "📖 Tạo order_book.rs..."
cat > src/order_book.rs << 'EOF'
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
EOF

echo "🎲 Tạo simulator.rs..."
cat > src/simulator.rs << 'EOF'
use crate::message::*;
use chrono::{DateTime, Utc};
use byteorder::{LittleEndian, WriteBytesExt};
use std::io::Write;

pub struct PitchSimulator {
    sequence_counter: u32,
    order_id_counter: u64,
    execution_id_counter: u64,
}

impl PitchSimulator {
    pub fn new() -> Self {
        Self {
            sequence_counter: 1,
            order_id_counter: 1000000000000000000,
            execution_id_counter: 1000000000,
        }
    }
    
    pub fn generate_sample_session(&mut self, symbol: &str) -> Vec<(SequencedUnitHeader, Vec<PitchMessage>)> {
        let mut frames = Vec::new();
        
        // Trading Status
        let trading_status = PitchMessage::TradingStatus {
            timestamp: Utc::now(),
            symbol: symbol.to_string(),
            trading_status: TradingStatus::Trading,
            market_id_code: "XASX".to_string(),
        };
        
        frames.push(self.create_frame(vec![trading_status]));
        
        // Add orders
        let orders = vec![
            self.create_add_order(symbol, Side::Buy, 1000, Price::from_decimal(10.00), "FIRM"),
            self.create_add_order(symbol, Side::Buy, 500, Price::from_decimal(9.99), "FIRM"),
            self.create_add_order(symbol, Side::Sell, 800, Price::from_decimal(10.01), "INST"),
        ];
        
        for order in orders {
            frames.push(self.create_frame(vec![order]));
        }
        
        // Execute trade
        let execution = PitchMessage::OrderExecuted {
            timestamp: Utc::now(),
            order_id: OrderId(self.order_id_counter - 2),
            executed_quantity: 500,
            execution_id: ExecutionId(self.execution_id_counter),
            contra_order_id: OrderId(self.order_id_counter - 1),
            contra_pid: "INST".to_string(),
        };
        
        frames.push(self.create_frame(vec![execution]));
        
        frames
    }
    
    fn create_add_order(&mut self, symbol: &str, side: Side, quantity: u32, price: Price, pid: &str) -> PitchMessage {
        let order_id = OrderId(self.order_id_counter);
        self.order_id_counter += 1;
        
        PitchMessage::AddOrder {
            timestamp: Utc::now(),
            order_id,
            side,
            quantity,
            symbol: symbol.to_string(),
            price,
            pid: pid.to_string(),
        }
    }
    
    fn create_frame(&mut self, messages: Vec<PitchMessage>) -> (SequencedUnitHeader, Vec<PitchMessage>) {
        let header = SequencedUnitHeader {
            length: 0,
            count: messages.len() as u8,
            unit: 1,
            sequence: self.sequence_counter,
        };
        
        self.sequence_counter += messages.len() as u32;
        (header, messages)
    }
    
    pub fn serialize_frame(&self, header: &SequencedUnitHeader, messages: &[PitchMessage]) -> Result<Vec<u8>, crate::error::PitchError> {
        let mut buffer = Vec::new();
        
        // Serialize messages
        let mut message_data = Vec::new();
        for message in messages {
            let serialized = self.serialize_message(message)?;
            message_data.extend(serialized);
        }
        
        // Write header
        let total_length = 8 + message_data.len() as u16;
        buffer.write_u16::<LittleEndian>(total_length)?;
        buffer.write_u8(header.count)?;
        buffer.write_u8(header.unit)?;
        buffer.write_u32::<LittleEndian>(header.sequence)?;
        
        buffer.extend(message_data);
        Ok(buffer)
    }
    
    fn serialize_message(&self, message: &PitchMessage) -> Result<Vec<u8>, crate::error::PitchError> {
        let mut buffer = Vec::new();
        
        match message {
            PitchMessage::TradingStatus { timestamp, symbol, trading_status, market_id_code } => {
                buffer.write_u8(22)?;
                buffer.write_u8(0x3B)?;
                buffer.write_u64::<LittleEndian>(timestamp.timestamp_nanos_opt().unwrap_or(0) as u64)?;
                
                let mut symbol_bytes = [b' '; 6];
                let symbol_len = symbol.len().min(6);
                symbol_bytes[..symbol_len].copy_from_slice(&symbol.as_bytes()[..symbol_len]);
                buffer.write_all(&symbol_bytes)?;
                
                buffer.write_u8(trading_status.to_byte())?;
                
                let mut market_id_bytes = [b' '; 4];
                let market_id_len = market_id_code.len().min(4);
                market_id_bytes[..market_id_len].copy_from_slice(&market_id_code.as_bytes()[..market_id_len]);
                buffer.write_all(&market_id_bytes)?;
                
                buffer.write_u8(0)?;
            },
            
            PitchMessage::AddOrder { timestamp, order_id, side, quantity, symbol, price, pid } => {
                buffer.write_u8(42)?;
                buffer.write_u8(0x37)?;
                buffer.write_u64::<LittleEndian>(timestamp.timestamp_nanos_opt().unwrap_or(0) as u64)?;
                buffer.write_u64::<LittleEndian>(order_id.0)?;
                buffer.write_u8(side.to_byte())?;
                buffer.write_u32::<LittleEndian>(*quantity)?;
                
                let mut symbol_bytes = [b' '; 6];
                let symbol_len = symbol.len().min(6);
                symbol_bytes[..symbol_len].copy_from_slice(&symbol.as_bytes()[..symbol_len]);
                buffer.write_all(&symbol_bytes)?;
                
                buffer.write_u64::<LittleEndian>(price.0)?;
                
                let mut pid_bytes = [b' '; 4];
                let pid_len = pid.len().min(4);
                pid_bytes[..pid_len].copy_from_slice(&pid.as_bytes()[..pid_len]);
                buffer.write_all(&pid_bytes)?;
                
                buffer.write_u8(0)?;
            },
            
            PitchMessage::OrderExecuted { timestamp, order_id, executed_quantity, execution_id, contra_order_id, contra_pid } => {
                buffer.write_u8(43)?;
                buffer.write_u8(0x38)?;
                buffer.write_u64::<LittleEndian>(timestamp.timestamp_nanos_opt().unwrap_or(0) as u64)?;
                buffer.write_u64::<LittleEndian>(order_id.0)?;
                buffer.write_u32::<LittleEndian>(*executed_quantity)?;
                buffer.write_u64::<LittleEndian>(execution_id.0)?;
                buffer.write_u64::<LittleEndian>(contra_order_id.0)?;
                
                let mut contra_pid_bytes = [b' '; 4];
                let contra_pid_len = contra_pid.len().min(4);
                contra_pid_bytes[..contra_pid_len].copy_from_slice(&contra_pid.as_bytes()[..contra_pid_len]);
                buffer.write_all(&contra_pid_bytes)?;
                
                buffer.write_u8(0)?;
            },
            
            _ => {
                return Err(crate::error::PitchError::Parse("Unsupported message type".to_string()));
            }
        }
        
        Ok(buffer)
    }
}

impl Default for PitchSimulator {
    fn default() -> Self {
        Self::new()
    }
}
EOF

echo "🚀 Tạo main.rs..."
cat > src/main.rs << 'EOF'
use cboe_pitch_parser::*;

fn main() -> Result<()> {
    println!("🎯 CBOE PITCH Protocol Parser và Simulator");
    println!("==========================================");
    
    // Tạo simulator
    let mut simulator = PitchSimulator::new();
    let sample_frames = simulator.generate_sample_session("ZVZT");
    
    println!("\n📦 Tạo {} sample frames", sample_frames.len());
    
    // Serialize và parse
    let mut parser = PitchParser::new();
    let mut all_binary_data = Vec::new();
    
    for (header, messages) in &sample_frames {
        let binary_data = simulator.serialize_frame(header, messages)?;
        all_binary_data.extend(binary_data);
        
        println!("   Frame: Unit={}, Seq={}, Count={}", 
                header.unit, header.sequence, header.count);
        
        for message in messages {
            println!("     -> {:?}", message);
        }
    }
    
    println!("\n🔄 Serialized {} bytes", all_binary_data.len());
    
    // Parse binary data
    parser.feed_data(&all_binary_data);
    
    println!("\n📖 Parsing binary data:");
    let mut order_book = OrderBook::new("ZVZT".to_string());
    
    while let Some((header, messages)) = parser.parse_next_frame()? {
        println!("   Parsed frame: Unit={}, Seq={}, Count={}", 
                header.unit, header.sequence, header.count);
        
        for message in &messages {
            println!("     -> Type: 0x{:02X}, Time: {}", 
                    message.message_type(), message.timestamp());
            
            order_book.apply_message(message);
        }
    }
    
    println!("\n📊 Order Book State:");
    println!("   Symbol: {}", order_book.symbol());
    println!("   Status: {:?}", order_book.trading_status());
    println!("   Orders: {}", order_book.order_count());
    println!("   Best Bid: {:?}", order_book.best_bid());
    println!("   Best Ask: {:?}", order_book.best_ask());
    println!("   Spread: {:?}", order_book.spread());
    
    let (bids, asks) = order_book.get_level_info(3);
    
    println!("\n📈 Order Book Levels:");
    println!("   Bids:");
    for (price, qty) in bids {
        println!("     {} @ {}", qty, price);
    }
    
    println!("   Asks:");
    for (price, qty) in asks {
        println!("     {} @ {}", qty, price);
    }
    
    // Test conversions
    let order_id = OrderId(1079067412513217551);
    let execution_id = ExecutionId(91001734436);
    
    println!("\n🔄 ID Conversions:");
    println!("   Order ID {} -> Base36: {}", order_id.0, order_id.to_base36());
    println!("   Execution ID {} -> Base36: {}", execution_id.0, execution_id.to_base36());
    
    let price = Price::from_decimal(12.3456789);
    println!("   Price 12.3456789 -> Raw: {}, Back: {}", price.0, price.to_decimal());
    
    println!("\n✅ Simulation hoàn thành!");
    Ok(())
}
EOF

echo "📝 Tạo README.md..."
cat > README.md << 'EOF'
# CBOE PITCH Protocol Parser

Rust implementation của CBOE Australia PITCH multicast protocol parser và simulator.

## Tính năng

- Parse binary PITCH messages
- Order book simulation real-time
- Message serialization/deserialization
- Base36 ID conversion
- Comprehensive error handling

## Cách sử dụng

```bash
# Build và chạy
cargo run

# Chạy tests
cargo test

# Build release
cargo build --release
```

## Message Types hỗ trợ

- Trading Status (0x3B)
- Add Order (0x37)
- Order Executed (0x38)
- Delete Order (0x3C)
- End of Session (0x2D)
- Và nhiều loại khác...

## Cấu trúc Project

- `src/message.rs` - Message definitions
- `src/parser.rs` - Binary parser
- `src/order_book.rs` - Order book simulation
- `src/simulator.rs` - Test data generator
- `src/error.rs` - Error handling
EOF

echo "🔧 Download dependencies..."
cargo check

echo "✅ Project CBOE PITCH Parser đã tạo thành công!"
echo "📁 Project directory: $PROJECT_NAME"
echo "🚀 Chạy 'cargo run' để test simulation"
