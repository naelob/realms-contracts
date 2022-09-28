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

from contracts.settling_game.interfaces.IERC1155 import IERC1155

from openzeppelin.access.ownable.library import Ownable

from openzeppelin.access.ownable.library import Ownable

from openzeppelin.upgrades.library import Proxy

from openzeppelin.introspection.erc165.library import ERC165

from contracts.token.library import ERC1155

struct CallOption {
    Writer : felt,
    Expiration : felt,
    Strike : felt,
    Premium : felt,
    Underlying : felt,
    AssetId ; felt,
}

@event
func CallOptionOpened(
    option_id : felt,
    writer : felt,
    strike : felt,
    expiration_time : felt,
    token_address : felt,
    token_id : felt
) {
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
func options_counter() -> (res: felt) {
}

@storage_var
func options_contracts_list(idx : felt) -> (call_option : CallOption) {
}

@storage_var
func market_paused() -> (bool: felt) {
}


@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    currency_address_ : felt
) {
    currency_address.write(currency_address_);
    Proxy.initializer(proxy_admin);
    Ownable.initializer(proxy_admin);
    market_paused.write(FALSE);
    options_counter.wirte(1);
    return ();
}

@external 
func upgrade{}(
    new_implementation : felt
) {
    Ownable.assert_only_owner();
    Proxy._set_implmentation_hash(new_implementation);
    return ();
}


/// Option Writer Functions ///


func write{} (
    token_address : felt,
    token_id : felt,
    strike : felt,
    expiration_time : felt
) {
    let (paused) = assert_not_paused();
    with_attr error_message("Covered_Call : Not Paused") {
        assert paused = FALSE;
    }
    let (caller) = get_caller_address();

    // ensure at least 24h is set for expiration
    let (timestamp) = get_block_timestamp();
    let twenty_four_hours = timestamp + 86400;
    assert_lt(twenty_four_hours, expiration_time);

    // assert that token_address is an ERC1155 and not the address of LORDS
    let (currency_address) = currency_address.read();
    assert_not_equal(currency_address, token_address);

    let (count) = options_counter.read()
    options_counter.write(count + 1);

    // add the new option contract to the opened contracts list
    local option_info : CallOption = CallOption(
        caller,
        expiration_time,
        strike,
        ,
        token_address,
        token_id
    );
    options_contracts_list.write(count, option_info);

    CallOptionOpened.emit(
        count,
        caller,
        strike,
        expiration_time,
        token_address,
        token_id
    );
}

// Internal

func _new_contract{}() -> (option_id : felt){
}

// Modifiers

func assert_not_paused{}() -> (paused : felt){
    let (paused) = market_paused.read();
    return paused;
}