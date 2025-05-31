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
