%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IVault {
    func set_new_asset_owner(asset_id : felt, to : felt) {}

    func release_underlying(asset_id : felt, to :felt) {}
}