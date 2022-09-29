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

from contracts.token.constants import (
    ON_ERC1155_RECEIVED_SELECTOR,
    ON_ERC1155_BATCH_RECEIVED_SELECTOR,
)

//
// STRUCTS
//

namespace SwapStatus {
    const Open = 1;
    const Executed = 2;
    const Cancelled = 3;
}

struct ResourcesNeeded {
    MIN_WOOD : Uint256,
    MIN_STONE : Uint256,
    MIN_COAL : Uint256,
    MIN_COPPER : Uint256,
    MIN_OBSIDIAN : Uint256,
    MIN_SILVER : Uint256,
    MIN_IRONWOOD : Uint256,
    MIN_COLD_IRON : Uint256,
    MIN_GOLD : Uint256,
    MIN_HARTWOOD : Uint256,
    MIN_DIAMONDS : Uint256,
    MIN_SAPPHIRE : Uint256,
    MIN_RUBY : Uint256,
    MIN_DEEP_CRYSTAL : Uint256,
    MIN_IGNUM : Uint256,
    MIN_ETHEREAL_SILICA : Uint256,
    MIN_TRUE_ICE : Uint256,
    MIN_TWILIGHT_QUARTZ : Uint256,
    MIN_ALCHEMICAL_SILVER : Uint256,
    MIN_ADAMANTINE : Uint256,
    MIN_MITHRAL : Uint256,
    MIN_DRAGONHIDE : Uint256,

}

struct Trade {
    owner : felt,
    asset_contract: felt,
    asset_ids: Uint256*,
    asset_ids_len : felt,
    asset_amounts : Uint256*,
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
    _token_amounts : Uint256*, 
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

    // check if expiration is valid
    let (block_timestamp) = get_block_timestamp();
    with_attr error_message("P2P_Market : Expiration Is Not Valid") {
        assert_nn_le(block_timestamp, expiration);
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

    let (caller) = get_caller_address();
    let (this_address) = get_contract_address();
    let (trade) = _trades.read(_trade_id);
        
    let (token_address) = asset_address.read();

    assert trade.status = TradeStatus.Open;

    assert_time_in_range(_trade_id);    

    _check_if_party_owns_needs(trade.needs, caller);
    
    // transfer items to contract
    IERC1155.safeBatchTransferFrom(
        token_address, 
        trade.owner, 
        this_address, 
        trade.asset_ids_len,
        trade.asset_ids,
        trade.asset_amounts_len,
        trade.asset_amounts,
        0, 
        null
    );

    local null : felt* = alloc();

    onERC1155BatchReceived(
        caller, 
        trade.owner,
        trade.asset_ids_len,
        trade.asset_ids,
        trade.asset_amounts_len,
        trade.asset_amounts,
        0, 
        null
    );

    // transfer items to buyer
    IERC1155.safeBatchTransferFrom(
        token_address, 
        this_address, 
        caller, 
        trade.asset_ids_len,
        trade.asset_ids,
        trade.asset_amounts_len,
        trade.asset_amounts,
        0, 
        null
    );

    local asset_ids_ : felt* = alloc();
    local index_i = 1;
    let (local ids : felt*) = _asset_ids_loop{
        syscall_ptr=syscall_ptr, pedersen_ptr=pedersen_ptr, range_check_ptr=range_check_ptr, start=index_i
    }(asset_ids_len);

    local asset_amounts : Uint256* = alloc();
    let (local amounts : Uint256*) = _asset_amounts_loop(asset_amounts, trade.needs);

    // transfer buyer's goods (what the writer of the swap actually needs in exchange) to creator of swap
    IERC1155.safeBatchTransferFrom(
        token_address, 
        caller, 
        trade.owner, 
        22,
        ids,
        22,
        amounts,
        0, 
        null
    );

    local trade_executed : Trade = Trade(
        trade.owner,
        trade.asset_contract,
        trade.asset_ids,
        trade.asset_ids_len,
        trade.asset_amounts,
        trade.asset_amounts_len,
        TradeStatus.Executed,
        trade.needs,
        trade.expiration
    );
    _trades.write(_trade_id, trade_executed);

    TradeExecuted.emit(_trade_id, caller);

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

@external
func onERC1155Received{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt, from_: felt, id: Uint256, amount: Uint256, data_len: felt, data: felt*
) -> (selector: felt) {

    return (ON_ERC1155_RECEIVED_SELECTOR);
}

@external
func onERC1155BatchReceived(
    operator: felt,
    from_: felt,
    ids_len: felt,
    ids: Uint256*,
    amounts_len: felt,
    amounts: Uint256*,
    data_len: felt,
    data: felt*,
) -> (selector: felt) {
    
    return (ON_ERC1155_BATCH_RECEIVED_SELECTOR);

}

@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interface_id: felt
) -> (success: felt) {
    return ERC165.supports_interface(interface_id);
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
func get_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    idx: felt
) -> (
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
    return (trade.status);
}

@view
func paused{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    paused: felt
) {
    let (paused) = Pausable.is_paused();
    return (paused);
}

//
// SETTERS 
//

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

func _check_if_party_owns_needs{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    needs : ResourcesNeeded, caller : felt
){
    alloc_locals;
    // ERC1155 contract address
    let (token_address) = asset_address.read();

    local asset_amounts : Uint256* = alloc();
    let (local amounts : Uint256*) = _asset_amounts_loop(asset_amounts, trade.needs);

    local asset_ids_ : Uint256* = alloc();
    local index_i = Uint256(1,0);
    let (local ids : Uint256*) = _asset_ids_loop{
        syscall_ptr=syscall_ptr, pedersen_ptr=pedersen_ptr, range_check_ptr=range_check_ptr, start=index_i
    }(asset_ids_len);

    let (balance_len : felt, balance : Uint256*) = IERC1155.balanceOfBatch(token_address, 1, [caller], 22, ids);

    _assert_amounts(start=0, amounts=amounts, balance=balance);
    return ();
}

func _assert_amounts{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    start=0, amounts : Uint256*, balance : Uint256*
) { 
    if (start == 22) {
        return ();
    }
    with_attr error_message("P2P_Market : Error Inside Asserting Needs Amounts") {
        uint256_le([amounts], [balance]);
    }
    return _assert_amounts(start=start+1, amounts=amounts + Uint256.SIZE, balance=balance+ Uint256.SIZE);
}

// returns an array [1....22]
func _asset_ids_loop{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, start : Uint256}(
    assets_ids : Uint256*
) -> (res : Uint256*){
    let (bool) = uint256_eq(start, Uint256(23,0));
    if (bool == 1) {
        return (res=assets_ids);
    }
    assert [assert_ids] = start;
    local new_start = uint256_add(start, Uint256(1,0));
    return _asset_ids_loop{
        syscall_ptr=syscall_ptr, pedersen_ptr=pedersen_ptr, range_check_ptr=range_check_ptr, start=new_start
    }(assets_ids=assets_ids + Uint256.SIZE);
}

// returns an array with the amounts matching the struct ResourceNeeded
func _asset_amounts_loop{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    assets_amounts : Uint256*, needs : ResourcesNeeded
) -> (res : Uint256*){
  
    assert [assets_amounts] = needs.MIN_WOOD;
    assert [assets_amounts + 1 * Uint256.SIZE] = needs.MIN_STONE;
    assert [assets_amounts + 2 * Uint256.SIZE] = needs.MIN_COAL;
    assert [assets_amounts + 3 * Uint256.SIZE] = needs.MIN_COPPER;
    assert [assets_amounts + 4 * Uint256.SIZE] = needs.MIN_OBSIDIAN;
    assert [assets_amounts + 5 * Uint256.SIZE] = needs.MIN_IRONWOOD;
    assert [assets_amounts + 6 * Uint256.SIZE] = needs.MIN_COLD_IRON;
    assert [assets_amounts + 7 * Uint256.SIZE] = needs.MIN_GOLD;
    assert [assets_amounts + 8 * Uint256.SIZE] = needs.MIN_HARTWOOD;
    assert [assets_amounts + 9 * Uint256.SIZE] = needs.MIN_DIAMONDS;
    assert [assets_amounts + 10 * Uint256.SIZE] = needs.MIN_SAPPHIRE;
    assert [assets_amounts + 11 * Uint256.SIZE] = needs.MIN_RUBY; 
    assert [assets_amounts + 12 * Uint256.SIZE] = needs.MIN_DEEP_CRYSTAL; 
    assert [assets_amounts + 13 * Uint256.SIZE] = needs.MIN_IGNUM;
    assert [assets_amounts + 14 * Uint256.SIZE] = needs.MIN_ETHEREAL_SILICA;
    assert [assets_amounts + 15 * Uint256.SIZE] = needs.MIN_TRUE_ICE;
    assert [assets_amounts + 16 * Uint256.SIZE] = needs.MIN_TWILIGHT_QUARTZ;
    assert [assets_amounts + 17 * Uint256.SIZE] = needs.MIN_ALCHEMICAL_SILVER;
    assert [assets_amounts + 18 * Uint256.SIZE] = needs.MIN_ADAMANTINE;
    assert [assets_amounts + 19 * Uint256.SIZE] = needs.MIN_MITHRAL;
    assert [assets_amounts + 20 * Uint256.SIZE] = needs.MIN_DRAGONHIDE;
    
    return (res=assets_amounts);
}

