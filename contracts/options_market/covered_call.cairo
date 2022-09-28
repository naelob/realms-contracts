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

from openzeppelin.access.ownable.library import Ownable

from openzeppelin.upgrades.library import Proxy

from openzeppelin.introspection.erc165.library import ERC165

from contracts.token.library import ERC1155

from starkware.cairo.common.bool import TRUE, FALSE

struct CallOption {
    Writer : felt,
    VaultAddress : felt,
    Expiration : felt,
    Strike : felt,
    Premium : felt,
    Underlying : felt,
    AssetId : felt,
    Settled : felt
    Bid : felt,
    Winner : felt
}
struct SettleType {
    Auction : felt,
    Spot : felt
}

@event
func CallOptionOpened(
    option_id : felt,
    writer : felt,
    vault_address : felt,
    strike : felt,
    expiration_time : felt,
    token_address : felt,
    token_id : felt
) {
}

@event
func CallOptionBurned(
    option_id : felt,
) {
}

@event
func CallOptionReclaimed(
    option_id : felt,
) {
}

@event
func CallOptionSettledByAuction(
    option_id : felt,
){
}

@event
func CallOptionSettledBySpot(
    option_id : felt,
){
}

@event
func OptionBought(
    option_id : felt
){
}

@event
func Bid(
    option_id : felt, bid_amount : felt, bidder : felt
){
}


@event
func MarketPaused(
    bool : felt
) {
}

func CallOptionEarningsClaimed(
    option_id : felt, owner_of_option_contract : felt, claimable : felt) {
}

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
func options_contracts_list(idx : felt) -> (call_option : CallOption) {
}

@storage_var
func assets_to_options(vault_address : felt, token_id : felt) -> (call_option : CallOption) {
}
@storage_var
func option_claims(option_id : felt) -> (amount_claimable: felt) {
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


@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    currency_address_ : felt,
    vault_address_ : felt,
    nft_contract_adress_ : felt,
    settle_type_ : felt,
    min_above_bid_alpha_ : felt,
    auction_start_period_ : felt
) {
    currency_address.write(currency_address_);
    vault_address.write(vault_address_);
    nft_address.write(nft_contract_adress_);
    Proxy.initializer(proxy_admin);
    Ownable.initializer(proxy_admin);
    market_paused.write(FALSE);
    options_counter.wirte(1);
    settle_type.write(settle_type_);
    min_above_bid_alpha.write(min_above_bid_alpha_);
    auction_start_period.write(auction_start_period_);
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


/// Option Writer Functions ///

@external
func write{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    token_address : felt,
    token_id : felt,
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

    let (count) = options_counter.read();

    let (this_address) = get_contract_address();
    let (vault_address) = vault_address.read();
    // Transfer the ERC1155 underlying into our contract
    IERC1155.safeTransferFrom(token_address, writer, vault_address, token_id, 1, 0, [0]);
    // TODO : add a check to make sure ownership of the ERC1155 is set to our vault

    // Mint an NFT ERC721 to the writer of the option
    // This ERC721 would represent the option contract held by the writer, can be traded on the NFT marketplace
    let (nft_address) = nft_address.read()
    IERC721._safeMint(nft_address, writer, count, 0, [0]);

    
    options_counter.write(count + 1);
    let premium : felt;
    let (settle_type) = settle_type.read();
    if (settle_type == SettleType.Auction) { 
        // we'll use an auction system where users can start bidding one day before expiration
        // The starting bid will be set at the strike price + 5% for e.g
        premium = strike;
    } else {
        // Spot so we must give the nft option contract a fair price maybe Black Scholes ? 
        // TODO : determine the right premium price for the ERC1155 being sent into the contract
        premium = 200;
    }
 
    local option_info : CallOption = CallOption(    
        caller,
        vault_address,
        expiration_time,
        strike,
        premium,
        token_address,
        token_id,
        FALSE,
        0,
        0
    )
    options_contracts_list.write(count, option_info);

    // Add our option tied to the token_id of the ERC1155
    assets_to_options.write(vault_address, token_id, option_info);

    CallOptionOpened.emit(
        count,
        caller,
        vault_address,
        strike,
        expiration_time,
        token_address,
        token_id
    );
    return ();
}

@external
func bid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt, bid_amount : felt
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

    with_attr error_message("Covered_Call :Overbid Not Sufficicient : Must Be Above Strike Price") {
        let actual_bid = option_info.Bid;
        let strike = option_info.Strike;
        assert_lt(strike_price, actual_bid);
    }

    _send_last_bid_to_previous_winner(option_info);
    IVault.set_new_asset_owner(option_info.VaultAddress, option_info.AssetId, caller);

    Bid.emit(option_id, bid_amount, caller);

    return ();

}

@external
func buy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
) {
    // TODO 
    let (caller) = get_caller_address();
    // Maybe it would be better to calc the premium here
    // as time may have passed since the emission of the option from the writer side
    // TODO : dont forget to remove the premium price set inside write func
    OptionBought.emit(option_emit, caller);
}
@external 
func settle{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
) {
    let (settle_type) = settle_type.read();
    if (settle_type == SettleType.Auction) { 
        return _settle_auction(option_id);
    }else {
        return _settle_spot(option_id);
    }
}

@external
func reclaim_underlying{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
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
        option_info.VaultAddress,
        option_info.Expiration,
        option_info.Strike,
        option_info.Premium,
        option_info.Underlying,
        option_info.AssetId,
        TRUE,
        option_info.Bid,
        option_info.Winner,
    )
    options_contracts_list.write(option_id, new_option_info);


    IVault.release_underlying(option_info.VaultAddress, option_info.AssetId, option_info.Writer);

    CallOptionReclaimed.emit(option_id);
    return ();
}   

@external
func claim_option_earnings{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
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

    IERC20.transferFrom(currency_address, contract, caller, [claimable]);

    return ();

}

@external
func burn_expired_option{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(  
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
        option_info.VaultAddress,
        option_info.Expiration,
        option_info.Strike,
        option_info.Premium,
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

// Internal

func _settle_auction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(option_id : felt){
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
        option_info.VaultAddress,
        option_info.Expiration,
        option_info.Strike,
        option_info.Premium,
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
        IERC20.transferFrom(currency_address, contract, owner_of_option_contract, [spread]);
        IERC721._burn(nft_address, option_id);
        CallOptionSettledByAuction.emit(option_id);
        return ();
    }

    // It enables the owner of the option to get the spread later if by any chance he is not the caller of the function bid
    option_claims.write(option_id, spread);
    CallOptionSettledByAuction.emit(option_id);
    return ();

    // misc : The ERC1155 ownership is changed inside the bid function when a highest bidder is set

}

func _settle_spot{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
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
        option_info.VaultAddress,
        option_info.Expiration,
        option_info.Strike,
        option_info.Premium,
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
    
    let (spot_price_resource) = _get_spot_price(option_info.AssetId);

    with_attr error_message("Covered_Call : ERC1155 Resource Is Worth 0") {
        assert_not_zero(spot_price_resource);
    }

    let (strike_price) = option_info.Strike;
    let (res) = is_le(strike_price, spot_price_resource);
    if (res == 1) {
        // send the strike price amount to the option writer
        IERC20.transferFrom(currency_address, owner_of_option_contract, option_info.Writer, [option_info.Strike]); 
        // give ownership of underlying ERC1155 resource to the holder of the option
        IVault.set_new_asset_owner(option_info.VaultAddress, option_info.AssetId, caller);
    }

    // option is worthless : so we burn it ? 
    IERC721._burn(nft_address, option_id);
    CallOptionSettledBySpot.emit(option_id);
    return ();
}


func _get_spot_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    asset_id : felt
) {
    // TODO : call the get_all_rates([asset_id], [1]) function inside Exchange AMM btwn ERC1155 <> LORDS
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
    IERC20.transferFrom(currency_address, this_address, call_option.Winner, [bid]);
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
}

// Modifiers

func assert_bid_is_enabled{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    option_id : felt
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

func assert_not_paused{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (paused : felt){
    let (paused) = market_paused.read();
    return (paused);
}
func assert_settlement{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (res : felt) {
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