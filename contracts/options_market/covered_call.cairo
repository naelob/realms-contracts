%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.math import assert_nn, assert_le, assert_not_zero
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_sub,
    uint256_mul,
    uint256_unsigned_div_rem,
    uint256_le,
    uint256_lt,
    uint256_eq,
)
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.token.erc721.IERC721 import IERC721

from contracts.settling_game.interfaces.IERC1155 import IERC1155

from openzeppelin.access.ownable.library import Ownable

from openzeppelin.upgrades.library import Proxy

from openzeppelin.introspection.erc165.library import ERC165

from contracts.token.library import ERC1155

from starkware.cairo.common.bool import TRUE, FALSE

from contracts.options_market.interfaces.IBlackScholes import IBlackScholes
from contracts.options_market.interfaces.IExhangeAMM import IExhangeAMM

//////
//// STRUCTS ////
//////

struct CallOption {
    Writer : felt,
    Expiration : felt,
    Strike : felt, // Uint256 ?
    Underlying : felt, // Uint256 ?
    AssetId : Uint256,
    Settled : felt
    Bid : felt, // Uint256 ?
    Winner : felt
}

struct SettleType {
    Auction : felt,
    Spot : felt
}

struct ResourceAsset {
    Beneficiary : felt,
    TokenAddress : felt,
    AssetId : Uint256
}

//////
//// EVENTS ////
//////

@event
func CallOptionOpened(
    option_id : Uint256,
    writer : felt,
    strike : felt,
    expiration_time : felt,
    token_address : felt,
    token_id : Uint256
) {
}

@event
func CallOptionBurned(
    option_id : Uint256,
) {
}

@event
func CallOptionReclaimed(
    option_id : Uint256,
) {
}

@event
func CallOptionSettledByAuction(
    option_id : Uint256,
){
}

@event
func CallOptionSettledBySpot(
    option_id : Uint256,
){
}

@event
func OptionBought(
    option_id : Uint256, premium : felt
){
}

@event
func Bid(
    option_id : Uint256, bid_amount : felt, bidder : felt
){
}

@event
func MarketPaused(
    bool : felt
) {
}

func CallOptionEarningsClaimed(
    option_id : Uint256, owner_of_option_contract : felt, claimable : felt) {
}


//////
//// STORAGE ////
//////

// Contract Address of ERC20 address for this swap contract
@storage_var
func currency_address() -> (res: felt) {
}

// Contract Address of ERC1155 address for this swap contract
@storage_var
func underlying_token_address() -> (res: felt) {
}

@storage_var
func nft_address() -> (res: felt) {
}

@storage_var
func options_counter() -> (res: felt) {
}

@storage_var
func options_contracts_list(idx : Uint256) -> (call_option : CallOption) {
}

@storage_var
func assets_to_options(token_id : Uint256) -> (call_option : CallOption) {
}

@storage_var
func option_claims(option_id : Uint256) -> (amount_claimable: felt) {
}

@storage_var
func settle_type() -> (res: felt) {
}

@storage_var
func auction_start_period() -> (res: felt) {
}

@storage_var
func market_paused() -> (bool: felt) {
}

@storage_var
func min_above_bid_alpha() -> (res: felt) {
}

@storage_var
func black_scholes_address() -> (res: felt) {
}

@storage_var
func assets_owned_by_this_contract(owner : felt) -> (res: ResourceAsset) {
}


//////
//// CONSTRUCTOR ////
//////

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    currency_address_ : felt,
    nft_contract_adress_ : felt,
    settle_type_ : felt,
    min_above_bid_alpha_ : felt,
    auction_start_period_ : felt,
    black_scholes_address_ : felt,
    exchange_amm_address : felt
) {
    currency_address.write(currency_address_);
    nft_address.write(nft_contract_adress_);
    Proxy.initializer(proxy_admin);
    Ownable.initializer(proxy_admin);
    market_paused.write(FALSE);
    options_counter.wirte(Uint256(1,0));
    settle_type.write(settle_type_);
    min_above_bid_alpha.write(min_above_bid_alpha_);
    auction_start_period.write(auction_start_period_);
    black_scholes_address.write(black_scholes_address_);
    exchange_amm_address.write(exchange_amm_address_);
    return ();
}

@external 
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_implementation : felt
) {
    Ownable.assert_only_owner();
    Proxy._set_implmentation_hash(new_implementation);
    return ();
}


//////
//// GETTERS ////
//////


//////
//// SETTERS ////
//////



//////
//// EXTERNAL ////
//////

@external
func write{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    token_address : felt,
    token_id : Uint256,
    strike : felt,
    expiration_time : felt,
) {
    alloc_locals;
    let (paused) = assert_not_paused();
    with_attr error_message("Covered_Call : Not Paused") {
        assert paused = FALSE;
    }

    // make sure a settlement type is written in storage
    let (is_set) = assert_settlement();
    with_attr error_message("Covered_Call : Settle Type Not Set") {
        assert_not_zero(is_set);
    }

    let (caller) = get_caller_address();

    // ensure at least 24h is set for expiration
    let (timestamp) = get_block_timestamp();
    let twenty_four_hours = timestamp + 86400;
    assert_lt(twenty_four_hours, expiration_time);
 
    // assert that token_address is an ERC1155 and not the address of LORDS
    let (currency_address) = currency_address.read();
    assert_not_equal(currency_address, token_address);

    let (count : Uint256) = options_counter.read();

    let (this_address) = get_contract_address();
    // Transfer the ERC1155 underlying into our contract
    local data : Uint256* = alloc();
    assert [data] = caller;
    assert [data + 1] = token_address;
    assert [data + 2] = token_id;

    IERC1155.safeTransferFrom(token_address, writer, this_address, token_id, Uint256(1, 0), 3, data);
    // TODO : add a check to make sure ownership of the ERC1155 is set to our address;

    // Mint an NFT ERC721 to the writer of the option
    // This ERC721 would represent the option contract held by the writer, can be traded on the NFT marketplace
    let (nft_address) = nft_address.read();
    IERC721._safeMint(nft_address, writer, count, 0, null);

    let next_count : Uint256 = uint256_add(count, Uint256(1,0));
    options_counter.write(next_count);
 
    local option_info : CallOption = CallOption(    
        caller,
        expiration_time,
        strike,
        token_address,
        token_id,
        FALSE,
        0,
        0
    )
    options_contracts_list.write(count, option_info);

    // Add our option tied to the token_id of the ERC1155
    assets_to_options.write(token_id, option_info);

    CallOptionOpened.emit(
        count,
        caller,
        strike,
        expiration_time,
        token_address,
        token_id
    );
    return ();
}

@external
func bid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256, bid_amount : felt
) {
    assert_bid_is_enabled(option_id);

    let (caller) = get_caller_address();
    let (currency_address) = currency_address.read();
    let (balance_LORDS) = IERC20.balanceOf(currency_address, caller);
    with_attr error_message("Covered_Call : Not Enough Balance") {
        assert_lt(bid_amount, balance_LORDS);
    }
    let (option_info : CallOption) = options_contracts_list.read(option_id);

    // maybe to change via DAO, but by default option writer cant bid its own option creation
    with_attr error_message("Covered_Call : Writer Cannot Bid Its Own Contract") {
        assert_not_equal(caller, option_info.Writer);
    }

    with_attr error_message("Covered_Call : Increment below MinAboveBidAlpha : Overbid Not Sufficicient") {
        let actual_bid = option_info.Bid;
        let (min_above_bid_alpha_) = min_above_bid_alpha.read();
        let mul = actual_bid * min_above_bid_alpha_;
        let (res) = unsigned_div_rem(mul, 10000);
        let (final) = res + actual_bid;
        assert_lt(final, bid_amount);
    }

    with_attr error_message("Covered_Call : Overbid Not Sufficicient : Must Be Above Strike Price") {
        let actual_bid = option_info.Bid;
        let strike = option_info.Strike;
        assert_lt(strike_price, actual_bid);
    }

    _send_last_bid_to_previous_winner(option_info);
    _set_new_asset_owner(option_info.AssetId, caller);

    Bid.emit(option_id, bid_amount, caller);

    return ();

}

@external
func buy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
) {
    alloc_locals;
    let (caller) = get_caller_address();
    // Maybe it would be better to calc the premium here
    // as time may have passed since the emission of the option from the writer side

    let (currency_address) = currency_address.read();
    let (this_address)  = get_contract_address();
    let (nft_address) = nft_address.read();

    let (option_info : CallOption) = options_contracts_list.read(option_id);

    // maybe to change via DAO, but by default option writer cant bid its own option creation
    with_attr error_message("Covered_Call : Writer Cannot Buy Its Own Contract") {
        assert_not_equal(caller, option_info.Writer);
    }
    let (bs_address) = black_scholes_address.read();
    let (spot_price_resource) = _get_spot_price(option_info.AssetId);

    // TODO : pad each value to 27 digits and normalize expiration on annual basis
    // we assume for sake of simplicity 
    // - IR to 0%
    // - Volatitlity to 20
    let (local call_option_price, _) = IBlackScholes.option_prices(
        bs_address,
        option_info.Expiration,
        200000000000000000000000000,
        spot_price_resource,
        option_info.Strike,
        00000000000000000000000000 
    );

    // TODO : convert call_option to uint256
    IERC20.transferFrom(currency_address, caller, this_address, [call_option_price]);

    let (owner) = IERC721.owner_of(nft_address, option_id);
    IERC721.transferFrom(nft_address, owner, caller, option_id);

    OptionBought.emit(option_id, caller, call_option_price);
    return ();
}
@external 
func settle{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
) {
    let (settle_type) = settle_type.read();
    if (settle_type == SettleType.Auction) { 
        return _settle_auction(option_id);
    } else {
        return _settle_spot(option_id);
    }
}

@external
func reclaim_underlying{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (option_info : CallOption) = options_contracts_list.read(option_id);
    with_attr error_message("Covered_Call : Only Writer Allowed") {
        assert caller == option_info.Writer;
    }
    let (is_settled) = option_info.Settled;
    with_attr error_message("Covered_Call : Option Already Settled") {
        assert is_settled == FALSE;
    }
    let (nft_address) = nft_address.read();
    let (owner) = IERC721.owner_of(nft_address, option_id);
    with_attr error_message("Covered_Call : Not The Owner of the Option Contract") {
        assert owner == caller;
    }

    with_attr error_message("Covered_Call : Option Expired") {
        let (timestamp) = get_block_timestamp();
        assert_lt(timestamp, option_info.Expiration);
    }

    //burn the option NFT 
    IERC721._burn(nft_address, option_id);


    // settle the option to TRUE
  
    local new_option_info : CallOption = CallOption(
        option_info.Writer,
        option_info.Expiration,
        option_info.Strike,
        option_info.Underlying,
        option_info.AssetId,
        TRUE,
        option_info.Bid,
        option_info.Winner,
    )
    options_contracts_list.write(option_id, new_option_info);


    _release_underlying(option_info.AssetId, option_info.Writer);

    CallOptionReclaimed.emit(option_id);
    return ();
}   

@external
func claim_option_earnings{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
) {
    let (owner_of_option_contract) = IERC721.owner_of(nft_address, option_id);
    let (caller) = get_caller_address();

    with_attr error_message("Covered_Call : You Must Be Owner Of The Option To Claim Earnings") {
        assert owner_of_option_contract = caller;
    }

    let (claimable) = option_claims.read(option_id);
    option_claims.write(option_id, 0);
    with_attr error_message("Covered_Call : Nothing To Claim") {
        assert_not_zero(claimable);
    }
    IERC721._burn(nft_address, option_id);
    CallOptionEarningsClaimed.emit(option_id, owner_of_option_contract, claimable);

    // TODO : convert claimable to Uint256
    IERC20.transferFrom(currency_address, contract, caller, [claimable]);

    return ();

}

@external
func burn_expired_option{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(  
    option_id : Uint256
) {
    alloc_locals;
    let (option_info : CallOption) = options_contracts_list.read(option_id);

    with_attr error_message("Covered_Call : Option Not Expired") {
        let (timestamp) = get_block_timestamp();
        assert_lt(option_info.Expiration, timestamp);
    }

    let (is_settled) = option_info.Settled;
    with_attr error_message("Covered_Call : Option Already Settled") {
        assert is_settled == FALSE;
    }

    // TODO : check if settle type is Auction, and make sure no actual bids are present


    let (nft_address) = nft_address.read();
    //burn the option NFT 
    IERC721._burn(nft_address, option_id);
    
    local new_option_info : CallOption = CallOption(
        option_info.Writer,
        option_info.Expiration,
        option_info.Strike,
        option_info.Underlying,
        option_info.AssetId,
        TRUE,
        option_info.Bid,
        option_info.Winner,
    )
    options_contracts_list.write(option_id, new_option_info);

    CallOptionBurned.emit(option_id);

    return ();
}

@external
func onERC1155Received{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt, from_: felt, id: Uint256, amount: Uint256, data_len: felt, data: felt*
) -> (selector: felt) {
    // receive ERC1155 token and store inside a mapping : owner => {token_address, token_id} 
    // [data] => owner_of_asset
    // [data + 1] => token_address
    // [data + 2] => token_id

    // TODO : convert [data + 2] to Uint256
    local resource : ResourceAsset = ResourceAsset(
        [data],
        [data + 1], 
        [data + 2]
    );
    local owner = [data];
    let asset_id = [data + 2];
    assets_owned_by_this_contract.write(asset_id, resource);
    return (ON_ERC1155_RECEIVED_SELECTOR);

}

//////
//// INTERNAL ////
//////

func _set_new_asset_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    asset_id : Uint256, new_owner : felt
){  
    with_attr error_message("Covered_Call : New Owner Cannot Be Zero") {
        assert_not_zero(new_owner);
    }

    let (resource : ResourceAsset) = assets_owned_by_this_contract.read(asset_id);
    
    // TODO : add a check for valid resource MUST BE DIFFERENT THAN NULL(0,0,0)

    let new_resource : ResourceAsset =  ResourceAsset(
        new_owner
        resource.TokenAddress,
        resource.AssetId
    );
    assets_owned_by_this_contract.write(asset_id, new_resource);
    return ();
}

func _release_underlying{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    asset_id : Uint256, owner : felt
){
    alloc_locals;

    with_attr error_message("Covered_Call : Owner Cannot Be Zero") {
        assert_not_zero(owner);
    }
    // TODO : add a check for valid asset id

    let (resource : ResourceAsset) = assets_owned_by_this_contract.read(asset_id);

    // TODO : add a check for valid resource MUST BE DIFFERENT THAN NULL(0,0,0)

    with_attr error_message("Covered_Call : Owner Must Own The Underlying") {
        assert resource.Beneficiary = owner;
    }
    let (this_address) = get_contract_address();
    local null : Uint256* = alloc();
    IERC1155.safeTransferFrom(resource.TokenAddress, this_address, owner, asset_id, Uint256(1, 0), 0, null);

    let null_resource : ResourceAsset = ResourceAsset(
        0,
        0,
        Uint256(0,0)
    );
    assets_owned_by_this_contract.write(asset_id, null_resource);
    return ();
}

func _settle_auction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
){
    alloc_locals;
    let (option_info : CallOption) = options_contracts_list.read(option_id);

    with_attr error_message("Covered_Call : Option Must Be Expired") {
        let (timestamp) = get_block_timestamp();
        assert_lt(option_info.Expiration, timestamp);
    }
    with_attr error_message("Covered_Call : Option Must Have A Highest Bidder") {
        assert_not_zero(option_info.Winner);
    }

    with_attr error_message("Covered_Call : Option Already Settled") {
        let (is_settled) = option_info.Settled;
        assert is_settled == FALSE;
    }

    let spread = option_info.bid - option_info.strike;
    
    // settle the option to TRUE
    local new_option_info : CallOption = CallOption(
        option_info.Writer,
        option_info.Expiration,
        option_info.Strike,
        option_info.Underlying,
        option_info.AssetId,
        TRUE,
        option_info.Bid,
        option_info.Winner,
    )
    options_contracts_list.write(option_id, new_option_info);
    
    
    let (owner_of_option_contract) = IERC721.owner_of(nft_address, option_id);

    let (nft_address) = nft_address.read();
    let (currency_address) = currency_address.read();

    let (contract) = get_contract_address();

    // send the strike price amount to the option writer
    IERC20.transferFrom(currency_address, contract, option_info.Writer, [option_info.Strike]);
    let (caller) = get_caller_address();
    if (caller == owner_of_option_contract) {
        //send the spread to the option owner 
        // TODO convert spread to uint256
        IERC20.transferFrom(currency_address, contract, owner_of_option_contract, [spread]);
        IERC721._burn(nft_address, option_id);
        CallOptionSettledByAuction.emit(option_id);
        // transfer ERC1155 to winner of auction
        _transfer_asset(option_info.AssetId);
        return ();
    }

    // It enables the owner of the option to get the spread later if by any chance he is not the caller of the function bid
    option_claims.write(option_id, spread);
    CallOptionSettledByAuction.emit(option_id);
    return ();

    // misc : The ERC1155 ownership is changed inside the bid function when a highest bidder is set

}

func _settle_spot{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
){
    alloc_locals;
    let (option_info : CallOption) = options_contracts_list.read(option_id);

    with_attr error_message("Covered_Call : Option Must Be Expired") {
        let (timestamp) = get_block_timestamp();
        assert_lt(option_info.Expiration, timestamp);
    }
    let (owner_of_option_contract) = IERC721.owner_of(nft_address, option_id);
    let (caller) = get_caller_address();

    with_attr error_message("Covered_Call : Only Owner/Buyer Of The Option Can Exercise") {
        assert owner_of_option_contract = caller;
    }


    // settle the option to TRUE
    local new_option_info : CallOption = CallOption(
        option_info.Writer,
        option_info.Expiration,
        option_info.Strike,
        option_info.Underlying,
        option_info.AssetId,
        TRUE,
        option_info.Bid,
        option_info.Winner,
    )
    options_contracts_list.write(option_id, new_option_info);
    
    

    let (nft_address) = nft_address.read();
    let (currency_address) = currency_address.read();

    let (contract) = get_contract_address();

    // Writer of option gets the strike price and holder of option of the same option receives 
    // the ERC1155 resource only and only if spot_price_at_expiration(ERC1155_resource) > strike_price
    
    let (spot_price_resource : Uint256) = _get_spot_price(option_info.AssetId);

    with_attr error_message("Covered_Call : ERC1155 Resource Is Worth 0") {
        assert_not_zero(spot_price_resource);
    }

    // TODO : convert everything to Uint256 
    let (strike_price) = option_info.Strike;
    let (res) = is_le(strike_price, spot_price_resource);
    if (res == 1) {
        // send the strike price amount to the option writer
        // TODO convert strike to Uint256
        IERC20.transferFrom(currency_address, owner_of_option_contract, option_info.Writer, [option_info.Strike]); 
        // give ownership of underlying ERC1155 resource to the holder of the option
        _set_new_asset_owner(option_info.AssetId, caller);
        // transfer ERC1155 to the beneficiary
        _transfer_asset(option_info.AssetId);
    }

    // option is worthless : so we burn it ? 
    IERC721._burn(nft_address, option_id);
    CallOptionSettledBySpot.emit(option_id);
    return ();
}

func _get_spot_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    asset_id : Uint256
) -> (res : Uint256) {
    let (exchange_amm_address) = exchange_amm_address.read();
    // get prices from amm exchange for ERC1155 resource
    let (prices : Uint256*, _) = IExhangeAMM.get_all_rates(exchange_amm_address, 1, [asset_id], 1, [Uint256(1,0)]);
    return (res=[prices]);
}

func _send_last_bid_to_previous_winner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    call_option : CallOption
){
    let (bid) = call_option.Bid;
    with_attr error_message("Covered_Call : Bid Must Not Be Zero") {
        assert_not_zero(bid);
    }
    let (currency_address) = currency_address.read();
    let (this_address) = get_contract_address();
    // TODO : convert bid to Uint256
    IERC20.transferFrom(currency_address, this_address, call_option.Winner, [bid]);
    return ();
}

func _set_market_paused{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bool : felt
){  
    Ownable.assert_only_owner();

    with_attr error_message("Covered_Call : Already Paused") {
        let (is_paused) = assert_not_paused();
        assert is_paused == FALSE;
    }
    market_paused.write(TRUE);
    MarketPaused.emit(bool);
    return ();
}

func _transfer_asset{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    asset_id : Uint256
){
    alloc_locals;
    // TODO : add a check for valid asset id

    let (resource : ResourceAsset) = assets_owned_by_this_contract.read(asset_id);

    // TODO : add a check for valid resource MUST BE DIFFERENT THAN NULL(0,0,0)

    let (this_address) = get_contract_address();
    local null : Uint256* = alloc();
    IERC1155.safeTransferFrom(resource.TokenAddress, this_address, resource.Beneficiary, asset_id, Uint256(1, 0), 0, null);

    let null_resource : ResourceAsset = ResourceAsset(
        0,
        0,
        Uint256(0,0)
    );
    assets_owned_by_this_contract.write(asset_id, null_resource);
    return ();
}
//////
//// MODIFIERS ////
//////

func assert_bid_is_enabled{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : Uint256
){
    let (option_info : CallOption) = options_contracts_list.read(option_id);

    with_attr error_message("Covered_Call : Option Expired") {
        let (timestamp) = get_block_timestamp();
        assert_lt(timestamp, option_info.Expiration);
    }

    let (auction_start_period) = auction_start_period.read();
    let (diff) =  option_info.Expiration - auction_start_period;
    with_attr error_message("Covered_Call : You Can Only Bid On Last Day") {
        let (timestamp) = get_block_timestamp();
        assert_lt(diff, timestamp);
    }

    let (is_settled) = option_info.Settled;
    with_attr error_message("Covered_Call : Option Already Settled") {
        assert is_settled == FALSE;
    }
}   
func assert_not_paused{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) -> (paused : felt){
    let (paused) = market_paused.read();
    return (paused);
}
func assert_settlement{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) -> (res : felt) {
    let (type) = settle_type.read();
    assert_not_zero(type);
    if (type == SettleType.Auction) {
        return (res=1);
    }
    
    if (type == SettleType.Spot) {
        return (res=1);
    } 
    return (res=0);
}