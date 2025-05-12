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
            shares_trading::init(test_scenario::ctx(&mut scenario));
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
            shares_trading::init(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(1000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                1, // 购买1个share
                &mut coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, SUBJECT);
            test_scenario::return_shared(shares_trading);
        };
        
        // USER1购买SUBJECT的shares
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(1000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                2, // 购买2个share
                &mut coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, USER1);
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性以便后面的测试
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000, // 添加5000单位流动性
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
            shares_trading::init(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(1000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                5, // 购买5个share
                &mut coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, SUBJECT);
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性以便后面的测试
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000, // 添加5000单位流动性
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
            let coin = mint_sui(1000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                2, // 购买2个share
                &mut coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, USER1);
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
            shares_trading::init(test_scenario::ctx(&mut scenario));
        };
        
        // SUBJECT购买第一个share
        test_scenario::next_tx(&mut scenario, SUBJECT);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(1000, test_scenario::ctx(&mut scenario));
            
            shares_trading::buy_shares(
                &mut shares_trading,
                SUBJECT,
                5, // 购买5个share
                &mut coin,
                test_scenario::ctx(&mut scenario)
            );
            
            // 返还剩余的SUI
            transfer::public_transfer(coin, SUBJECT);
            test_scenario::return_shared(shares_trading);
        };
        
        // 添加流动性
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let shares_trading = test_scenario::take_shared<SharesTrading>(&scenario);
            let coin = mint_sui(10000, test_scenario::ctx(&mut scenario));
            
            shares_trading::add_liquidity(
                &mut shares_trading,
                &mut coin,
                5000, // 添加5000单位流动性
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
    
    // 辅助函数：铸造SUI代币
    fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }
} 