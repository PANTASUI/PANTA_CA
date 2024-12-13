module panta::token
{
    use sui::bcs;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self,create_currency, Coin, TreasuryCap};
    use sui::tx_context::{Self,sender};
    use panta::icon::{get_icon_url};

    const EDirectorIsPaused: u64 = 1001;
    const ECLAIMIsPaused: u64 = 1002;

    // === Constants ===
    const MAX_SUPPLY: u64 = 50_000_000_000_000; // 50m (6 decimals)
    const LPCOIN: u64 = 15_000_000_000_000; // 15m (6 decimals)
    const MINTCOIN: u64 = 30_000_000_000_000; // 30m (6 decimals)
    const AIRDROPCOIN: u64 = 4_500_000_000_000; // 4.5m (6 decimals)
    const MIN_MINT:u64 = 15; 
    const MAX_MINT:u64 = 35; 

    public struct TOKEN has drop {}

    public struct AdminCap has store, key {
        id: UID,
    }


    public struct Director has key, store {
        id: UID,
        mintpaused: bool,
        claimpaused: bool,
        maxsupply: u64,
        mintsupply: u64,
        devaccount: address,
        treasury: TreasuryCap<TOKEN>
    }
    public struct Pantamint has key {
        id: UID,
        mintcoin: u64,
        coin: u64
    }
    fun init(witness: TOKEN, ctx: &mut TxContext)
    {
        let sender = tx_context::sender(ctx);
        let (treasury, metadata) = create_currency(
            witness,
            6, // decimals
            b"PANTA", // symbol
            b"PANTA", // name
            b"The First Fair Launch Memecoin in the East.", // description
            option::some(get_icon_url()), // icon_url
            ctx,
        );
        transfer::public_freeze_object(metadata);
        let mut director = Director {
            id: object::new(ctx),
            treasury,
            maxsupply: MAX_SUPPLY,
            mintpaused: true,
            mintsupply: 0,
            claimpaused: true,
            devaccount: sender
        };
        let mintcoin = LPCOIN + AIRDROPCOIN;
        coin::mint_and_transfer(&mut director.treasury,mintcoin,sender,ctx);
        transfer::share_object(director);
        
        let adminCap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(adminCap, ctx.sender());
    }
    // === Public-Mutative Functions ===
    entry fun new_user(
        director: &Director,
        ctx: &mut TxContext,
    ) {
        assert!(director.mintpaused == false, EDirectorIsPaused);
        let user_minter =  Pantamint {
            id: object::new(ctx),
            coin: 0,
            mintcoin: 0
        };
        transfer::transfer(user_minter, ctx.sender());
    }
    public fun destroy(
        user_minter: Pantamint,
    ) {
        let Pantamint { id,coin: _,mintcoin: _} = user_minter;
        id.delete();
    }
    public fun mint(
        director: &mut Director,
        user_minter: &mut Pantamint,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(director.mintpaused == false, EDirectorIsPaused);
        let sender = tx_context::sender(ctx);
        let tx_digest = tx_context::digest(ctx);
        let sender_bytes = bcs::to_bytes(&sender);
        let sender_value = (((*vector::borrow(&sender_bytes, 0) as u64) << 56) |
            ((*vector::borrow(&sender_bytes, 1) as u64) << 48) |
            ((*vector::borrow(&sender_bytes, 2) as u64) << 40) |
            ((*vector::borrow(&sender_bytes, 3) as u64) << 32) |
            ((*vector::borrow(&sender_bytes, 4) as u64) << 24) |
            ((*vector::borrow(&sender_bytes, 5) as u64) << 16) |
            ((*vector::borrow(&sender_bytes, 6) as u64) << 8) |
            (*vector::borrow(&sender_bytes, 7) as u64));
        let digest_value1 = (((*vector::borrow(tx_digest, 0) as u64) << 56) |
            ((*vector::borrow(tx_digest, 1) as u64) << 48) |
            ((*vector::borrow(tx_digest, 2) as u64) << 40) |
            ((*vector::borrow(tx_digest, 3) as u64) << 32));
        let digest_value2 = (((*vector::borrow(tx_digest, 4) as u64) << 24) |
            ((*vector::borrow(tx_digest, 5) as u64) << 16) |
            ((*vector::borrow(tx_digest, 6) as u64) << 8) |
            (*vector::borrow(tx_digest, 7) as u64));
        let current_timestamp = clock::timestamp_ms(clock);
        let combined = ((digest_value1 ^ sender_value) + 
                (digest_value2 * 17) + 
                current_timestamp) % 1000; 
        let range  = MAX_MINT - MIN_MINT;
        let result = MIN_MINT + (combined % range);
        let maxsupply = director.maxsupply;
        let dec_coin = 5 * 100000;

        assert!(director.mintsupply +  dec_coin + result * 1000000 <= maxsupply, 1009);

        let total_supply = coin::total_supply(&director.treasury);

        assert!(total_supply + result * 1000000 <= maxsupply, 1010);
        
        assert!(director.mintsupply + dec_coin + result * 1000000 <= MINTCOIN, 1010);
        user_minter.coin = user_minter.coin + result * 1000000;
        
        user_minter.mintcoin = user_minter.mintcoin + result * 1000000;
        
        coin::mint_and_transfer(&mut director.treasury,dec_coin,director.devaccount,ctx);
        director.mintsupply = director.mintsupply +  dec_coin + result * 1000000 ;
    }

    public fun claim(
        director: &mut Director,
        user_minter: &mut Pantamint,
        ctx: &mut TxContext,
    ) {
        assert!(director.claimpaused == false, ECLAIMIsPaused);
        let maxsupply = director.maxsupply;
        let total_supply = coin::total_supply(&director.treasury);
        assert!(total_supply + user_minter.coin <= maxsupply, 1009);
        //let coins = director.treasury.mint(user_minter.coin, ctx);
        let coins  = user_minter.coin;
        user_minter.coin = 0;
        coin::mint_and_transfer(&mut director.treasury,coins,sender(ctx),ctx);
    }

    // === Admin functions ===
    public fun set_dev_account(
        director: &mut Director,
        _: &AdminCap,
        newaddr:address
        )
    {
        director.devaccount = newaddr;
    }
    public fun admin_mintpause(
        director: &mut Director,
        _: &AdminCap,
    ) {
        director.mintpaused = true;
    }

    public fun admin_mintresume(
        director: &mut Director,
        _: &AdminCap,
    ) {
        director.mintpaused = false;
    }
    public fun admin_claimpause(
        director: &mut Director,
        _: &AdminCap,
    ) {
        director.claimpaused = true;
    }

    public fun admin_claimresume(
        director: &mut Director,
        _: &AdminCap,
    ) {
        director.claimpaused = false;
    }
    public fun admin_destroy(
        cap: AdminCap,
    ) {
        let AdminCap { id } = cap;
        id.delete();
    }
}
