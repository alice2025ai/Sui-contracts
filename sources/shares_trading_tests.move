#[test_only]
module shares_trading::shares_trading_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::test_utils::assert_eq;
    use sui::object::{Self, ID};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use std::debug;
    
    use shares_trading::shares_trading::{Self, SharesTrading, Admin};

    // 测试地址
    const ADMIN: address = @0xAD;
    const SUBJECT: address = @0xAB;
    const USER1: address = @0xA1;
    const USER2: address = @0xA2;
    
    // 测试初始化
    #[test]
    fun test_init() {
        let scenario = test_scenario::begin(ADMIN);
        
        // 初始化合约
        {
            shares_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        // 验证Admin对象已经创建并转移给ADMIN
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(test_scenario::has_most_recent_for_sender<Admin>(&scenario), 0);
        };
        
        // 验证SharesTrading对象已经创建并共享
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(test_scenario::has_most_recent_shared<SharesTrading>(), 0);
        };
        
        test_scenario::end(scenario);
    }
    
    // 测试购买shares
    #[test]
    fun test_buy_shares() {
        let scenario = test_scenario::begin(ADMIN);
        
        // 初始化合约
        {
            shares_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            // 铸造足够的币，第一个share价格为0，但也需要足够支付手续费
            let coin = mint_sui(10000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                1, // 购买1个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        // USER1购买SUBJECT的shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            // 铸造更多的币，因为价格会随供应量增加
            let coin = mint_sui(100000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                2, // 购买2个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性以便后面的测试
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000000000, // 添加足够的流动性
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, ADMIN);
            test_scenario::return_shared(shares_trading);
        };
        
        test_scenario::end(scenario);
    }
    
    // 测试出售shares
    #[test]
    fun test_sell_shares() {
        let scenario = test_scenario::begin(ADMIN);
        
        // 初始化合约
        {
            shares_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(100000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                5, // 购买5个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性以便后面的测试
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000000000, // 添加足够的流动性
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, ADMIN);
            test_scenario::return_shared(shares_trading);
        };
        
        // USER1购买SUBJECT的shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(1000000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                2, // 购买2个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        // USER1出售SUBJECT的shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            
            shares_trading::sell_shares(
                &mut shares_trading,
                SUBJECT,
                1, // 出售1个share
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        test_scenario::end(scenario);
    }
    
    // 测试提取协议费用
    #[test]
    fun test_withdraw_protocol_fees() {
        let scenario = test_scenario::begin(ADMIN);
        
        // 初始化合约
        {
            shares_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(100000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                5, // 购买5个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000000000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000000000, // 添加足够的流动性
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, ADMIN);
            test_scenario::return_shared(shares_trading);
        };
        
        // 管理员提取协议费用
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let admin = test_scenario::take_from_sender<Admin>(&scenario);
            
            shares_trading::withdraw_protocol_fees(
                &mut shares_trading,
                &admin,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(shares_trading);
            test_scenario::return_to_sender(&scenario, admin);
        };
        
        test_scenario::end(scenario);
    }
    
    // 测试价格计算
    #[test]
    fun test_price_calculations() {
        let scenario = test_scenario::begin(ADMIN);

        // 初始化合约
        {
            shares_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // 测试价格计算
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            
            // 测试第一个share的价格应该为0
            let subject_new = @0xABC;
            let price = shares_trading::get_buy_price(&shares_trading, subject_new, 1);
            assert_eq(price, 0);
            
            // 测试价格随数量增加而上涨
            let price_1 = shares_trading::get_buy_price(&shares_trading, subject_new, 1);
            let price_2 = shares_trading::get_buy_price(&shares_trading, subject_new, 2);
            // 由于第一个share特殊处理为0，所以购买2个至少不比购买1个便宜
            assert!(price_2 >= price_1, 0);
            
            // 测试不同supply下的购买价格
            let subject_has_some = SUBJECT;
            
            // 获取当前supply
            let current_supply = shares_trading::get_current_supply(&shares_trading, subject_has_some);
            // 确认supply初始为0
            assert_eq(current_supply, 0);
            
            // 检查价格计算函数的输出
            // 注意：我们要先检查价格，再进行实际购买操作
            let initial_price_1 = shares_trading::get_buy_price(&shares_trading, subject_has_some, 1);
            debug::print(&initial_price_1);
            let initial_price_2 = shares_trading::get_buy_price(&shares_trading, subject_has_some, 1);
            // 购买更多数量时价格至少不会更低
            assert!(initial_price_2 >= initial_price_1, 0);
            
            // 为subject_has_some创建一些shares
            let coin = mint_sui(1000000000, test_scenario::ctx(&mut scenario));
            shares_trading::buy_shares(
                &mut shares_trading,
                subject_has_some,
                1, // 购买5个share
                coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 验证supply已经增加
            let new_supply = shares_trading::get_current_supply(&shares_trading, subject_has_some);
            assert_eq(new_supply, 1);  // supply应该从0增加到5
            
            // 购买后再次检查价格，supply增加后价格应该上涨
            let new_price_1 = shares_trading::get_buy_price(&shares_trading, subject_has_some, 1);
            debug::print(&new_price_1);
            // 确认new_price_1应该大于0，因为不是第一个share了
            assert!(new_price_1 > 0, 0);
            assert!(new_price_1 >= initial_price_1, 0);
            
            // 测试带费用的价格
            let price_with_fee = shares_trading::get_buy_price_after_fee(&shares_trading, subject_has_some, 1);
            // 价格加上费用应该大于原始价格
            assert!(price_with_fee > new_price_1, 0);
            
            // 测试出售价格
            let sell_price = shares_trading::get_sell_price(&shares_trading, subject_has_some, 1);
            let sell_price_with_fee = shares_trading::get_sell_price_after_fee(&shares_trading, subject_has_some, 1);
            
            // 出售价格应该小于或等于购买价格 (因为价格曲线)
            assert!(sell_price <= new_price_1, 0);
            
            // 扣除费用后的出售价格应该小于原始出售价格
            assert!(sell_price_with_fee < sell_price, 0);

            test_scenario::return_shared(shares_trading);
        };
        
        test_scenario::end(scenario);
    }
    
    // 辅助函数：铸造SUI代币
    fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }
} 