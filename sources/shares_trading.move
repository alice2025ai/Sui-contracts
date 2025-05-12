module shares_trading::shares_trading {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::event;
    use sui::table::{Self, Table};
    use std::option::{Self, Option};

    // 错误码
    const EInsufficientPayment: u64 = 0;
    const EOnlySubjectCanBuyFirstShare: u64 = 1;
    const ECannotSellLastShare: u64 = 2;
    const EInsufficientShares: u64 = 3;
    const ETransferFailed: u64 = 4;
    const EInsufficientLiquidity: u64 = 5;

    // 常量
    const BASIS_POINTS: u64 = 10000;
    const PROTOCOL_FEE_PERCENT: u64 = 500; // 5%
    const SUBJECT_FEE_PERCENT: u64 = 500; // 5%

    // 事件
    struct Trade has copy, drop {
        trader: address,
        subject: address,
        is_buy: bool,
        amount: u64,
        price: u64,
        protocol_fee: u64,
        subject_fee: u64,
        supply: u64,
    }

    // 平台管理员
    struct Admin has key {
        id: UID,
        protocol_fee_destination: address,
    }

    // 主合约
    struct SharesTrading has key {
        id: UID,
        // 每个subject的shares总供应量
        shares_supply: Table<address, u64>,
        // 用户持有的shares余额 (subject -> (owner -> balance))
        shares_balance: Table<address, Table<address, u64>>,
        // 协议费用
        protocol_fee_balance: Balance<SUI>,
        // 流动性池
        liquidity_pool: Balance<SUI>,
    }

    // 初始化函数
    fun init(ctx: &mut TxContext) {
        let admin = Admin {
            id: object::new(ctx),
            protocol_fee_destination: tx_context::sender(ctx),
        };

        let shares_trading = SharesTrading {
            id: object::new(ctx),
            shares_supply: table::new(ctx),
            shares_balance: table::new(ctx),
            protocol_fee_balance: balance::zero(),
            liquidity_pool: balance::zero(),
        };

        transfer::share_object(shares_trading);
        transfer::transfer(admin, tx_context::sender(ctx));
    }

    // 计算价格的函数 (使用简单的线性定价公式: price = supply * amount)
    fun get_price(supply: u64, amount: u64): u64 {
        let price: u64 = 0;
        let i: u64 = 0;
        
        while (i < amount) {
            price = price + supply + i;
            i = i + 1;
        };
        
        price
    }

    // 购买shares
    public entry fun buy_shares(
        shares_trading: &mut SharesTrading,
        shares_subject: address,
        amount: u64,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // 检查shares_supply中是否存在shares_subject
        let supply = if (table::contains(&shares_trading.shares_supply, shares_subject)) {
            *table::borrow(&shares_trading.shares_supply, shares_subject)
        } else {
            // 如果不存在，初始化为0
            table::add(&mut shares_trading.shares_supply, shares_subject, 0);
            0
        };
        
        // 只有shares的主体才能购买第一个share
        assert!(supply > 0 || shares_subject == sender, EOnlySubjectCanBuyFirstShare);
        
        // 计算价格和费用
        let price = get_price(supply, amount);
        let protocol_fee = price * PROTOCOL_FEE_PERCENT / BASIS_POINTS;
        let subject_fee = price * SUBJECT_FEE_PERCENT / BASIS_POINTS;
        let total_cost = price + protocol_fee + subject_fee;
        
        // 检查支付是否足够
        assert!(coin::value(payment) >= total_cost, EInsufficientPayment);
        
        // 更新shares余额
        if (!table::contains(&shares_trading.shares_balance, shares_subject)) {
            table::add(&mut shares_trading.shares_balance, shares_subject, table::new(ctx));
        };
        
        let balances = table::borrow_mut(&mut shares_trading.shares_balance, shares_subject);
        
        if (!table::contains(balances, sender)) {
            table::add(balances, sender, 0);
        };
        
        let user_balance = table::borrow_mut(balances, sender);
        *user_balance = *user_balance + amount;
        
        // 更新供应量
        let supply_ref = table::borrow_mut(&mut shares_trading.shares_supply, shares_subject);
        *supply_ref = *supply_ref + amount;
        
        // 处理付款
        let paid = coin::split(payment, total_cost, ctx);
        let paid_balance = coin::into_balance(paid);
        
        // 提取协议费用
        let protocol_fee_balance = balance::split(&mut paid_balance, protocol_fee);
        balance::join(&mut shares_trading.protocol_fee_balance, protocol_fee_balance);
        
        // 提取主体费用并转移给shares_subject
        let subject_fee_coin = coin::from_balance(balance::split(&mut paid_balance, subject_fee), ctx);
        transfer::public_transfer(subject_fee_coin, shares_subject);
        
        // 剩余金额加入流动性池
        balance::join(&mut shares_trading.liquidity_pool, paid_balance);
        
        // 发出事件
        event::emit(Trade {
            trader: sender,
            subject: shares_subject,
            is_buy: true,
            amount,
            price,
            protocol_fee,
            subject_fee,
            supply: *supply_ref,
        });
    }

    // 出售shares
    public entry fun sell_shares(
        shares_trading: &mut SharesTrading,
        shares_subject: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // 获取当前供应量
        assert!(table::contains(&shares_trading.shares_supply, shares_subject), EInsufficientShares);
        let supply = *table::borrow(&shares_trading.shares_supply, shares_subject);
        
        // 不能出售最后一个share
        assert!(supply > amount, ECannotSellLastShare);
        
        // 检查用户是否有足够的shares
        assert!(table::contains(&shares_trading.shares_balance, shares_subject), EInsufficientShares);
        let balances = table::borrow_mut(&mut shares_trading.shares_balance, shares_subject);
        
        assert!(table::contains(balances, sender), EInsufficientShares);
        let user_balance = table::borrow_mut(balances, sender);
        assert!(*user_balance >= amount, EInsufficientShares);
        
        // 计算价格和费用
        let price = get_price(supply - amount, amount);
        let protocol_fee = price * PROTOCOL_FEE_PERCENT / BASIS_POINTS;
        let subject_fee = price * SUBJECT_FEE_PERCENT / BASIS_POINTS;
        let seller_amount = price - protocol_fee - subject_fee;
        
        // 检查流动性池是否有足够的资金
        assert!(balance::value(&shares_trading.liquidity_pool) >= price, EInsufficientLiquidity);
        
        // 更新用户余额
        *user_balance = *user_balance - amount;
        
        // 更新供应量
        let supply_ref = table::borrow_mut(&mut shares_trading.shares_supply, shares_subject);
        *supply_ref = *supply_ref - amount;
        
        // 从流动性池中提取资金
        // 提取卖家应得的金额
        let seller_coin = coin::from_balance(balance::split(&mut shares_trading.liquidity_pool, seller_amount), ctx);
        transfer::public_transfer(seller_coin, sender);
        
        // 提取协议费用
        let protocol_fee_balance = balance::split(&mut shares_trading.liquidity_pool, protocol_fee);
        balance::join(&mut shares_trading.protocol_fee_balance, protocol_fee_balance);
        
        // 提取主体费用并转移给shares_subject
        let subject_fee_coin = coin::from_balance(balance::split(&mut shares_trading.liquidity_pool, subject_fee), ctx);
        transfer::public_transfer(subject_fee_coin, shares_subject);
        
        // 发出事件
        event::emit(Trade {
            trader: sender,
            subject: shares_subject,
            is_buy: false,
            amount,
            price,
            protocol_fee,
            subject_fee,
            supply: *supply_ref,
        });
    }

    // 提取协议费用
    public entry fun withdraw_protocol_fees(
        shares_trading: &mut SharesTrading,
        admin: &Admin,
        ctx: &mut TxContext
    ) {
        let protocol_fee_amount = balance::value(&shares_trading.protocol_fee_balance);
        let protocol_fee_coin = coin::take(&mut shares_trading.protocol_fee_balance, protocol_fee_amount, ctx);
        transfer::public_transfer(protocol_fee_coin, admin.protocol_fee_destination);
    }

    // 更新协议费用目的地
    public entry fun update_protocol_fee_destination(
        admin: &mut Admin,
        new_destination: address,
        _ctx: &mut TxContext
    ) {
        admin.protocol_fee_destination = new_destination;
    }

    // 添加流动性
    public entry fun add_liquidity(
        shares_trading: &mut SharesTrading,
        payment: &mut Coin<SUI>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(coin::value(payment) >= amount, EInsufficientPayment);
        let liquidity = coin::split(payment, amount, ctx);
        balance::join(&mut shares_trading.liquidity_pool, coin::into_balance(liquidity));
    }
} 