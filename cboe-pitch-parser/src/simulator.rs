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
