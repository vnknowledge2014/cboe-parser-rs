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
