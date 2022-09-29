%lang starknet;
%builtins pedersen range_check bitwise

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IP2PMarket {
    
    func open_escrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _token_ids_len : felt, 
        _token_ids: Uint256*, 
        _token_amounts_len : felt,
        _token_amounts : Uint256*, 
        _resources_needed_len ; felt,
        _resources_needed ; felt*,
        _expiration : felt
    ){};

    func execute_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _trade_id : felt
    ){};

    func cancel_trade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _trade_id: felt
    ){};


}