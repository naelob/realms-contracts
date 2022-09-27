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
    AssetId ; felt,
    Expiration : felt,
    Strike : felt
}

// Contract Address of ERC20 address for this swap contract
@storage_var
func currency_address() -> (currency_address: felt) {
}

// Contract Address of ERC1155 address for this swap contract
@storage_var
func token_address() -> (token_address: felt) {
}

@storage_var
func options_contracts_list(idx : felt) -> (call_option : CallOption) {
}

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    token_address_ : felt,
    currency_address_ : felt
) {
    currency_address.write(currency_address_);
    token_address.write(token_address_);
    Proxy.initializer(proxy_admin);
    Ownable.initializer(proxy_admin);
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

