%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace ICoveredCall {
    func bid() {
    }

    func write() {}

    func buy() {}

    func settle() {}

    func reclaim_underlying() {}

    func claim_option_earnings() {}

    func burn_expired_option() {}
}