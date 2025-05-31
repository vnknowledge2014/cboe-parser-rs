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
