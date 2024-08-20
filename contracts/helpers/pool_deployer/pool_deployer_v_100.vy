# pragma version 0.3.10
# pragma evm-version paris

"""
@title CurvePoolDeployer
@custom:version 1.0.0
@author Curve.Fi
@license Copyright (c) Curve.Fi, 2020-2024 - all rights reserved
@notice Deploys pools with pre-defined (and editable) presets
"""

version: public(constant(String[8])) = "1.0.0"


enum PoolType:
    STABLESWAP
    STABLESWAPMETA
    TWOCRYPTOSWAP
    TRICRYPTOSWAP


# ----------------- Pool specific  parameters -----------------

struct FeeParams:
    static_fee: uint256
    offpeg_fee_multiplier: uint256
    mid_fee: uint256
    out_fee: uint256
    fee_gamma: uint256

struct BondingCurveParams:
    amplification_factor: uint256
    gamma: uint256

struct LiquidityRebalancingParams:
    allowed_extra_profit: uint256
    adjustment_step: uint256

struct PoolPreset:
    pool_type: PoolType
    bonding_curve: BondingCurveParams
    fee: FeeParams
    rebalancing_strategy: LiquidityRebalancingParams
    oracle_moving_average_window: uint256
    implementation_id: uint256


# ----------------- Asset specific parameters -----------------

struct AssetParams:
    coins: DynArray[address, MAX_COINS]
    rate_oracles: DynArray[address, MAX_COINS]
    method_ids: DynArray[bytes4, MAX_COINS]
    asset_types: DynArray[uint8, MAX_COINS]
    initial_prices: DynArray[uint256, MAX_COINS]
    base_pool: address

# ------------------------ Interfaces --------------------------


interface AddressProvider:
    def get_address(idx: uint256) -> address: view


interface StableSwapFactory:
    def deploy_plain_pool(
        _name: String[32],
        _symbol: String[10],
        _coins: DynArray[address, MAX_COINS],
        _A: uint256,
        _fee: uint256,
        _offpeg_fee_multiplier: uint256,
        _ma_exp_time: uint256,
        _implementation_idx: uint256,
        _asset_types: DynArray[uint8, MAX_COINS],
        _method_ids: DynArray[bytes4, MAX_COINS],
        _oracles: DynArray[address, MAX_COINS],
    ) -> address: nonpayable
    def deploy_metapool(
        _base_pool: address,
        _name: String[32],
        _symbol: String[10],
        _coin: address,
        _A: uint256,
        _fee: uint256,
        _offpeg_fee_multiplier: uint256,
        _ma_exp_time: uint256,
        _implementation_idx: uint256,
        _asset_type: uint8,
        _method_id: bytes4,
        _oracle: address,
    ) -> address: nonpayable

interface TwocryptoFactory:
    def deploy_pool(
        _name: String[64],
        _symbol: String[32],
        _coins: address[2],
        implementation_id: uint256,
        A: uint256,
        gamma: uint256,
        mid_fee: uint256,
        out_fee: uint256,
        fee_gamma: uint256,
        allowed_extra_profit: uint256,
        adjustment_step: uint256,
        ma_exp_time: uint256,
        initial_price: uint256,
    ) -> address: nonpayable

interface TricryptoFactory:
    def deploy_pool(
        _name: String[64],
        _symbol: String[32],
        _coins: address[3],
        _weth: address,
        implementation_id: uint256,
        A: uint256,
        gamma: uint256,
        mid_fee: uint256,
        out_fee: uint256,
        fee_gamma: uint256,
        allowed_extra_profit: uint256,
        adjustment_step: uint256,
        ma_exp_time: uint256,
        initial_prices: uint256[2],
    ) -> address: nonpayable

# ----------------------------------------------------------------------

MAX_COINS: constant(uint256) = 8
STABLESWAP_FACTORY: immutable(StableSwapFactory)
TWOCRYPTO_FACTORY: immutable(TwocryptoFactory)
TRICRYPTO_FACTORY: immutable(TricryptoFactory)

admin: public(address)
pool_presets: public(HashMap[String[60], PoolPreset])

deployer: immutable(address)


@external
def __init__(_address_provider: address):
    
    address_provider: AddressProvider = AddressProvider(_address_provider)

    TRICRYPTO_FACTORY = TricryptoFactory(address_provider.get_address(11))
    STABLESWAP_FACTORY = StableSwapFactory(address_provider.get_address(12))
    TWOCRYPTO_FACTORY = TwocryptoFactory(address_provider.get_address(13))
    
    deployer = msg.sender
    self.admin = deployer


@external
def deploy_pool(_name: String[64], _symbol: String[32], _preset_name: String[60], _asset_data: AssetParams) -> address:

    preset: PoolPreset = self.pool_presets[_preset_name]
    pool: address = empty(address)

    if preset.pool_type == PoolType.STABLESWAP:
        
        assert len(_name) <= 32, "_name too long for StableSwap Factory (>32)"
        assert len(_symbol) <= 10, "_symbol too long for StableSwap Factory (>10)"

        pool = STABLESWAP_FACTORY.deploy_plain_pool(
            slice(_name, 0, 32),
            slice(_symbol, 0, 10),
            _asset_data.coins,
            preset.bonding_curve.amplification_factor,
            preset.fee.static_fee,
            preset.fee.offpeg_fee_multiplier,
            preset.oracle_moving_average_window,
            preset.implementation_id,
            _asset_data.asset_types,
            _asset_data.method_ids,
            _asset_data.rate_oracles,
        )

    elif preset.pool_type == PoolType.TWOCRYPTOSWAP:

        _coins: address[2] = empty(address[2])
        _coins[0] = _asset_data.coins[0]
        _coins[1] = _asset_data.coins[1]

        pool = TWOCRYPTO_FACTORY.deploy_pool(
            _name,
            _symbol,
            _coins,
            preset.implementation_id,
            preset.bonding_curve.amplification_factor,
            preset.bonding_curve.gamma,
            preset.fee.mid_fee,
            preset.fee.out_fee,
            preset.fee.fee_gamma,
            preset.rebalancing_strategy.allowed_extra_profit,
            preset.rebalancing_strategy.adjustment_step,
            preset.oracle_moving_average_window,
            _asset_data.initial_prices[0],
        )

    elif preset.pool_type == PoolType.STABLESWAPMETA:

        assert len(_name) <= 32, "_name too long for StableSwap Factory (>32)"
        assert len(_symbol) <= 10, "_symbol too long for StableSwap Factory (>10)"

        pool = STABLESWAP_FACTORY.deploy_metapool(
            _asset_data.base_pool,
            slice(_name, 0, 32),
            slice(_symbol, 0, 10),
            _asset_data.coins[0],
            preset.bonding_curve.amplification_factor,
            preset.fee.static_fee,
            preset.fee.offpeg_fee_multiplier,
            preset.oracle_moving_average_window,
            preset.implementation_id,
            _asset_data.asset_types[0],
            _asset_data.method_ids[0],
            _asset_data.rate_oracles[0],
        )

    else:

        assert len(_asset_data.coins) == 3, "num coins cannot be greater than 3"

        _coins: address[3] = empty(address[3])
        _coins[0] = _asset_data.coins[0]
        _coins[1] = _asset_data.coins[1]
        _coins[2] = _asset_data.coins[2]

        _initial_prices: uint256[2] = empty(uint256[2])
        _initial_prices[0] = _asset_data.initial_prices[0]
        _initial_prices[1] = _asset_data.initial_prices[1]

        pool = TRICRYPTO_FACTORY.deploy_pool(
            _name,
            _symbol,
            _coins,
            empty(address),  # ETH <> WETH auto conversion is disabled, set WETH to zero address
            preset.implementation_id,
            preset.bonding_curve.amplification_factor,
            preset.bonding_curve.gamma,
            preset.fee.mid_fee,
            preset.fee.out_fee,
            preset.fee.fee_gamma,
            preset.rebalancing_strategy.allowed_extra_profit,
            preset.rebalancing_strategy.adjustment_step,
            preset.oracle_moving_average_window,
            _initial_prices,
        )

    return pool


# Admin methods

@external
def set_owner(_new_admin: address):
    
    assert msg.sender == deployer
    assert self.admin == deployer
    assert _new_admin != deployer

    self.admin = _new_admin


@external
def update_preset(name: String[60], preset: PoolPreset):
    assert msg.sender == self.admin  # dev: only admin can set preset
    self.pool_presets[name] = preset
