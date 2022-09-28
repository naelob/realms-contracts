from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IExhangeAMM {
    func get_all_rates(
        token_ids_len: felt, token_ids: Uint256*, token_amounts_len: felt, token_amounts: Uint256*
    ) -> (prices_len: felt, prices: Uint256*) {
    }
}