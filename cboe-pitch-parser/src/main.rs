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
