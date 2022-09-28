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

struct CallOption {
    Writer : felt,
    VaultAddress : felt,
    Expiration : felt,
    Strike : felt,
    Premium : felt,
    Underlying : felt,
    AssetId ; felt,
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
func settle_type() -> (res: felt) {
}

@storage_var
func market_paused() -> (bool: felt) {
}


@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proxy_admin : felt,
    currency_address_ : felt,
    vault_address_ : felt,
    nft_contract_adress_ : felt,
    settle_type_ : felt
) {
    currency_address.write(currency_address_);
    vault_address.write(vault_address_);
    nft_address.write(nft_contract_adress_);
    Proxy.initializer(proxy_admin);
    Ownable.initializer(proxy_admin);
    market_paused.write(FALSE);
    options_counter.wirte(1);
    settle_type.write(settle_type_);
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

@external
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

    // TODO : determine the right premium price for the ERC1155 being sent into the contract

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
        premium = strike;
    } else {

    }
    

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
func settle{}(
) {
}

@external
func reclaim_uynderlying{}(
) {
}

@external
func burn_expired_option{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    
) {
    
}
func 
// Internal

func _new_contract{}() -> (option_id : felt){
}

// Modifiers

func assert_not_paused{}() -> (paused : felt){
    let (paused) = market_paused.read();
    return paused;
}
func assert_settlement{}() -> (res : felt) {
    let (type) = settle_type.read();
    assert_not_zero(type);
    if (type == SettleType.Auction) {
        return 1;
    }
    
    if (type == SettleType.Spot) {
        return 1;
    } 
    return 0;
}