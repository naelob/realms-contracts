%lang starknet
%builtins pedersen range_check bitwise

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.messages import send_message_to_l1
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.math import assert_nn_le, unsigned_div_rem, assert_lt_felt
from starkware.cairo.common.uint256 import Uint256, uint256_le

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.token.erc721.IERC721 import IERC721
from contracts.settling_game.interfaces.IERC1155 import IERC1155

from contracts.token.library import ERC1155
from openzeppelin.introspection.erc165.library import ERC165

from openzeppelin.access.ownable.library import Ownable

from openzeppelin.security.pausable.library import Pausable
from contracts.settling_game.utils.general import scale, unpack_data


//
// STRUCTS
//

namespace SwapStatus {
    const Open = 1;
    const Executed = 2;
    const Cancelled = 3;
}

struct ResourcesNeeded {
    MIN_WOOD : felt,
    MIN_STONE : felt,
    MIN_COAL : felt,
    MIN_COPPER : felt,
    MIN_OBSIDIAN : felt,
    MIN_SILVER : felt,
    MIN_IRONWOOD : felt,
    MIN_COLD_IRON : felt,
    MIN_GOLD : felt,
    MIN_HARTWOOD : felt,
    MIN_DIAMONDS : felt,
    MIN_SAPPHIRE : felt,
    MIN_RUBY : felt,
    MIN_DEEP_CRYSTAL : felt,
    MIN_IGNUM : felt,
    MIN_ETHEREAL_SILICA : felt,
    MIN_TRUE_ICE : felt,
    MIN_TWILIGHT_QUARTZ : felt,
    MIN_ALCHEMICAL_SILVER : felt,
    MIN_ADAMANTINE : felt,
    MIN_MITHRAL : felt,
    MIN_DRAGONHIDE : felt,
}

struct Trade {
    owner : felt,
    asset_contract: felt,
    asset_ids: Uint256*,
    asset_ids_len : felt,
    asset_amounts : felt*,
    asset_amounts_len : felt,
    status: felt,  // from SwapStatus
    needs : ResourcesNeeded,
    expiration : felt
}

// 
// EVENTS
//

@event
func TradeOpened(trade: Trade) {
}

@event
func TradeCancelled(trade : Trade) {
}

@event
func TradeExecuted(trade : Trade, executor : felt) {
}

//
// Storage
// 

// Indexed list of all trades
@storage_var
func _trades(idx: felt) -> (trade: Trade) {
}

// The current number of trades
@storage_var
func trade_counter() -> (value: felt) {
}

@storage_var
func asset_address() -> (res: felt) {
}

//##############
// CONSTRUCTOR #
//##############

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    asset_token : felt
) {
    asset_address.write(asset_token);
    trade_counter.write(1);
    Proxy.initializer(proxy_admin);    
    Ownable.initializer(proxy_admin);
    return ();
}

//##################
// TRADE FUNCTIONS #
//##################

@external
func open_escrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token_ids_len : felt, 
    _token_ids: Uint256*, 
    _token_amounts_len : felt,
    _token_amounts : felt*, 
    _resources_needed_len ; felt,
    _resources_needed ; felt*,
    _expiration : felt
) {
    alloc_locals;
    Pausable.assert_not_paused();
    let (caller) = get_caller_address();
    let (contract_address) = get_contract_address();
    
    let (asset_address) = asset_address.read();
    // TODO 
    _assert_ownership(_token_ids_len, _token_ids, );

    let (block_timestamp) = get_block_timestamp();
    let (trade) = _trades.read(_trade);
    // check trade within
    with_attr error_message("P2P_Market : Expiration Is Not Valid") {
        assert_nn_le(block_timestamp, trade.expiration);
    }
    
    let (trade_count) = trade_counter.read();
    
    assert owner_of = caller;
    assert is_approved = 1;

    local needs : ResourcesNeeded = _get_needs(_resources_needed);

    local trade : Trade = Trade(
        caller,
        asset_address,
        _token_ids,
        _token_ids_len,
        _token_amounts,
        _token_amounts_len,
        TradeStatus.Open,
        needs,
        _expiration
    );
    _trades.write(trade_count, trade);

    // increment
    trade_counter.write(trade_count + 1);
    TradeOpened.emit(trade);

    return ();
}

@external
func execute_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _trade_id : felt
) {
    alloc_locals;
    Pausable.assert_not_paused();
    let (currency) = currency_token_address.read();

    let (caller) = get_caller_address();
    let (_treasury_address) = treasury_address.read();
    let (trade) = _trades.read(_trade);
    let (fee_bips) = protocol_fee_bips.read();

    assert trade.status = TradeStatus.Open;

    assert_time_in_range(_trade);

    // Fee is paid by seller
    let (fee, remainder) = unsigned_div_rem(trade.price * fee_bips, 10000);
    let base_seller_receives = trade.price - fee;

    // transfer to poster
    IERC20.transferFrom(currency, caller, trade.poster, Uint256(base_seller_receives, 0));

    // transfer to treasury
    IERC20.transferFrom(currency, caller, _treasury_address, Uint256(fee, 0));

    // transfer item to buyer
    IERC721.transferFrom(trade.token_contract, trade.poster, caller, trade.token_id);

    write_trade(
        _trade,
        Trade(
        trade.token_contract,
        trade.token_id,
        trade.expiration,
        trade.price,
        trade.poster,
        TradeStatus.Executed,
        _trade),
    );

    return ();
}

@external
func cancel_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _trade_id: felt
) {
    alloc_locals;
    Pausable.assert_not_paused();
    let (trade) = _trades.read(_trade_id);

    assert trade.status = TradeStatus.Open;

    assert_time_in_range(_trade);
    local cancelled_trade : Trade = Trade(
        trade.owner,
        trade.asset_contract,
        trade.asset_ids,
        trade.asset_ids_len,
        trade.asset_amounts,
        trade.asset_amounts_len,
        TradeStatus.Cancelled,
        trade.needs,
        trade.expiration
    );
    _trades.write(_trade_id, cancelled_trade);

    TradeCancelled.emit(trade);
    return ();
}

////
// MODIFIERS
///

func assert_time_in_range{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _trade_id : felt
) {
    let (block_timestamp) = get_block_timestamp();
    let (trade) = _trades.read(_trade);
    // check trade within
    assert_nn_le(block_timestamp, trade.expiration);

    return ();
}


func _uint_to_felt{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    value: Uint256
) -> (value: felt) {
    assert_lt_felt(value.high, 2 ** 123);
    return (value.high * (2 ** 128) + value.low,);
}

//##########
// GETTERS #
//##########

@view
func get_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(idx: felt) -> (
    trade: Trade
) {
    return _trades.read(idx);
}

@view
func get_trade_counter{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    value: felt
) {
    return trade_counter.read();
}

// Returns a trades status
@view
func get_trade_status{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (status: felt) {
    let (trade) = _trades.read(idx);
    return (trade.status,);
}

// Returns a trades token
@view
func get_trade_token_id{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (token_id: Uint256) {
    let (trade) = _trades.read(idx);
    return (trade.token_id,);
}

@view
func paused{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (paused: felt) {
    let (paused) = Pausable.is_paused();
    return (paused,);
}

//##########
// SETTERS #
//##########

// Set basis points
@external
func set_basis_points{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    basis_points: felt
) -> (success: felt) {
    Ownable.assert_only_owner();
    protocol_fee_bips.write(basis_points);
    return (1,);
}

@external
func pause{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    Ownable.assert_only_owner();
    Pausable._pause();
    return ();
}

@external
func unpause{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    Ownable.assert_only_owner();
    Pausable._unpause();
    return ();
}

//// 
//// INTERNAL
///

func _get_needs{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _resources_needed : felt*
) -> (struct : ResourcesNeeded){  

    local res : ResourcesNeeded = ResourcesNeeded(
        [_resources_needed],
        [_resources_needed + 1],
        [_resources_needed + 2],
        [_resources_needed + 3],
        [_resources_needed + 4],
        [_resources_needed + 5],
        [_resources_needed + 6],
        [_resources_needed + 7],
        [_resources_needed + 8],
        [_resources_needed + 9],
        [_resources_needed + 10],
        [_resources_needed + 11],
        [_resources_needed + 12],
        [_resources_needed + 13],
        [_resources_needed + 14],
        [_resources_needed + 15],
        [_resources_needed + 16],
        [_resources_needed + 17],
        [_resources_needed + 18],
        [_resources_needed + 19],
        [_resources_needed + 20],
        [_resources_needed + 21],
    );
    return (struct=res);
}

func _assert_ownership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token_ids_len, _token_ids, 
) {
    // TODO 
    let (owner_of) = IERC721.ownerOf(_token_contract, _token_id);
    let (is_approved) = IERC721.isApprovedForAll(_token_contract, caller, contract_address);
}
