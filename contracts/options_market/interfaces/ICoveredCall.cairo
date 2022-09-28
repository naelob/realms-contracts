%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace ICoveredCall {
    func bid(option_id : felt, bid_amount : felt) {
    }

    func write(token_address : felt, token_id : felt, strike : felt, expiration_time : felt) {
    }

    func buy(option_id : felt) {
    }

    func settle(option_id : felt) {
    }

    func reclaim_underlying(option_id : felt) {
    }

    func claim_option_earnings(option_id : felt) {
    }

    func burn_expired_option(option_id : felt) {
    }
}