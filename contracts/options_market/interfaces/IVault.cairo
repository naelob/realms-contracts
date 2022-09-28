%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IVault {
    func set_new_asset_owner(asset_id : Uint256, to : felt) {}

    func release_underlying(asset_id : Uint256, to :felt) {}
}