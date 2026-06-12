// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SubscriptionProtocol
 * @author RecurringPayments.xyz
 * @notice A decentralized subscription service where each monthly payment mints
 * an NFT as proof-of-payment. Subscriptions can be tracked as active or expired.
 *
 * ARCHITECTURE OVERVIEW
 * ─────────────────────
 * • Users call subscribe() to register and pay for the first period.
 * • Each successful payment mints a soulbound* NFT tied to that billing period.
 * • Users call renewSubscription() each period to stay active.
 * • Owner can adjust the fee, pause/unpause, and withdraw collected funds.
 * • isActive() returns true only if the subscriber's latest period hasn't expired.
 *
 * (*) NFTs are non-transferable by default (soulbound). Owner can toggle this.
 *
 * PERIOD MODEL
 * ────────────
 * One period = PERIOD_DURATION seconds (default 30 days).
 * A subscriber is "active" if block.timestamp < subscription.expiresAt.
 * Grace periods are NOT implemented — pay before expiry or you lapse.
 */
contract SubscriptionProtocol is ERC721URIStorage, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTANTS & IMMUTABLES
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Length of one subscription period (30 days).
    uint256 public constant PERIOD_DURATION = 30 days;

    /// @notice Maximum number of periods that can be pre-paid at once.
    uint256 public constant MAX_PREPAY_PERIODS = 12;

    // ─────────────────────────────────────────────────────────────────────────
    // STATE VARIABLES
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Fee charged per subscription period (in wei).
    uint256 public subscriptionFee;

    /// @notice Base URI prepended to all token metadata URIs.
    string public baseTokenURI;

    /// @notice When true, NFT transfers are blocked (soulbound mode).
    bool public soulbound = true;

    /// @notice When true, new subscriptions and renewals are paused.
    bool public paused = false;

    /// @notice Running counter used to assign unique token IDs.
    uint256 private _nextTokenId;

    // ─────────────────────────────────────────────────────────────────────────
    // DATA STRUCTURES
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Represents one subscriber's on-chain state.
     * @param expiresAt      Unix timestamp when the current period ends.
     * @param totalPeriodsPaid Total number of periods ever paid (historical count).
     * @param subscribedAt   Unix timestamp of the very first subscription.
     * @param active         True once the user has subscribed at least once.
     */
    struct Subscription {
        uint256 expiresAt;
        uint256 totalPeriodsPaid;
        uint256 subscribedAt;
        bool active;
    }

    /**
     * @notice Metadata attached to each payment NFT.
     * @param subscriber     Address that made the payment.
     * @param periodStart    Start of the paid period.
     * @param periodEnd      End of the paid period.
     * @param periodNumber   Which period this token represents for that subscriber.
     */
    struct PaymentRecord {
        address subscriber;
        uint256 periodStart;
        uint256 periodEnd;
        uint256 periodNumber;
    }

    /// @notice Maps subscriber address → Subscription state.
    mapping(address => Subscription) public subscriptions;

    /// @notice Maps token ID → PaymentRecord (immutable after minting).
    mapping(uint256 => PaymentRecord) public paymentRecords;

    /// @notice Maps subscriber address → all token IDs they own (payment history).
    mapping(address => uint256[]) public subscriberTokens;

    /// @notice Total ETH collected by the protocol (lifetime).
    uint256 public totalRevenue;

    // ─────────────────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────────────────

    event Subscribed(
        address indexed subscriber, uint256 indexed tokenId, uint256 periodStart, uint256 periodEnd, uint256 amountPaid
    );

    event Renewed(
        address indexed subscriber,
        uint256 indexed tokenId,
        uint256 periodStart,
        uint256 periodEnd,
        uint256 amountPaid,
        uint256 totalPeriodsPaid
    );

    event SubscriptionExpired(address indexed subscriber, uint256 expiredAt);

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event SoulboundToggled(bool soulbound);
    event Paused(address by);
    event Unpaused(address by);
    event Withdrawn(address indexed to, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────────────────────────────────

    modifier whenNotPaused() {
        require(!paused, "SubscriptionProtocol: contract is paused");
        _;
    }

    modifier onlySubscriber() {
        require(subscriptions[msg.sender].active, "SubscriptionProtocol: not a subscriber");
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _fee          Initial subscription fee in wei per period.
     * @param _baseTokenURI Base URI for NFT metadata (e.g. "ipfs://Qm.../").
     */
    constructor(uint256 _fee, string memory _baseTokenURI) ERC721("Subscription Receipt", "SUBRX") Ownable(msg.sender) {
        require(_fee > 0, "SubscriptionProtocol: fee must be > 0");
        subscriptionFee = _fee;
        baseTokenURI = _baseTokenURI;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CORE SUBSCRIPTION LOGIC
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Subscribe for the first time (or re-subscribe after full lapse).
     * @dev    Mints one payment NFT per period paid. Caller must send exactly
     * subscriptionFee × periods in ETH.
     * @param  periods  Number of periods to pay upfront (1–MAX_PREPAY_PERIODS).
     */
    function subscribe(uint256 periods) external payable nonReentrant whenNotPaused {
        require(periods >= 1 && periods <= MAX_PREPAY_PERIODS, "SubscriptionProtocol: invalid period count");

        // FIXED: Replaced Unicode em-dash with standard hyphen
        require(!isActive(msg.sender), "SubscriptionProtocol: already has active subscription - use renew");
        require(msg.value == subscriptionFee * periods, "SubscriptionProtocol: incorrect ETH amount");

        Subscription storage sub = subscriptions[msg.sender];

        // First-time subscriber setup
        if (!sub.active) {
            sub.subscribedAt = block.timestamp;
            sub.active = true;
        }

        uint256 start = block.timestamp;

        for (uint256 i = 0; i < periods; i++) {
            uint256 periodStart = start + (i * PERIOD_DURATION);
            uint256 periodEnd = periodStart + PERIOD_DURATION;
            sub.totalPeriodsPaid++;

            uint256 tokenId = _mintPaymentNFT(msg.sender, periodStart, periodEnd, sub.totalPeriodsPaid);

            emit Subscribed(msg.sender, tokenId, periodStart, periodEnd, subscriptionFee);
        }

        // expiresAt advances from current block by all purchased periods
        sub.expiresAt = start + (periods * PERIOD_DURATION);
        totalRevenue += msg.value;
    }

    /**
     * @notice Renew an existing (or very-recently-expired) subscription.
     * @dev    If called while still active, the new period is stacked onto
     * the existing expiresAt. If called after expiry, renewal starts
     * from block.timestamp (gap in coverage; no retroactive credit).
     * @param  periods  Number of periods to pay upfront (1–MAX_PREPAY_PERIODS).
     */
    function renewSubscription(uint256 periods) external payable nonReentrant whenNotPaused onlySubscriber {
        require(periods >= 1 && periods <= MAX_PREPAY_PERIODS, "SubscriptionProtocol: invalid period count");
        require(msg.value == subscriptionFee * periods, "SubscriptionProtocol: incorrect ETH amount");

        Subscription storage sub = subscriptions[msg.sender];

        // If expired, restart from now; otherwise extend from current expiry
        uint256 start = isActive(msg.sender) ? sub.expiresAt : block.timestamp;

        for (uint256 i = 0; i < periods; i++) {
            uint256 periodStart = start + (i * PERIOD_DURATION);
            uint256 periodEnd = periodStart + PERIOD_DURATION;
            sub.totalPeriodsPaid++;

            uint256 tokenId = _mintPaymentNFT(msg.sender, periodStart, periodEnd, sub.totalPeriodsPaid);

            emit Renewed(msg.sender, tokenId, periodStart, periodEnd, subscriptionFee, sub.totalPeriodsPaid);
        }

        sub.expiresAt = start + (periods * PERIOD_DURATION);
        totalRevenue += msg.value;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns true if `subscriber` has a currently active subscription.
     * @param  subscriber Address to check.
     */
    function isActive(address subscriber) public view returns (bool) {
        Subscription storage sub = subscriptions[subscriber];
        return sub.active && block.timestamp < sub.expiresAt;
    }

    /**
     * @notice Returns seconds remaining in the active period. 0 if expired.
     * @param  subscriber Address to check.
     */
    function timeRemaining(address subscriber) external view returns (uint256) {
        if (!isActive(subscriber)) return 0;
        return subscriptions[subscriber].expiresAt - block.timestamp;
    }

    /**
     * @notice Returns all token IDs (payment NFTs) owned by a subscriber.
     * @param  subscriber Address to query.
     */
    function getSubscriberTokens(address subscriber) external view returns (uint256[] memory) {
        return subscriberTokens[subscriber];
    }

    /**
     * @notice Full subscription summary for a given address.
     * @param  subscriber Address to query.
     * @return active_          Whether the subscription is currently active.
     * @return expiresAt_       Unix timestamp the subscription expires.
     * @return totalPeriodsPaid_ Number of periods ever paid by this subscriber.
     * @return subscribedAt_    Unix timestamp of first subscription.
     * @return secondsLeft_     Seconds until expiry (0 if expired).
     */
    function getSubscription(address subscriber)
        external
        view
        returns (
            bool active_,
            uint256 expiresAt_,
            uint256 totalPeriodsPaid_,
            uint256 subscribedAt_,
            uint256 secondsLeft_
        )
    {
        Subscription storage sub = subscriptions[subscriber];
        active_ = isActive(subscriber);
        expiresAt_ = sub.expiresAt;
        totalPeriodsPaid_ = sub.totalPeriodsPaid;
        subscribedAt_ = sub.subscribedAt;
        secondsLeft_ = active_ ? sub.expiresAt - block.timestamp : 0;
    }

    /**
     * @notice Returns the ETH cost to subscribe or renew for N periods.
     * @param  periods Number of periods.
     */
    function quoteCost(uint256 periods) external view returns (uint256) {
        return subscriptionFee * periods;
    }

    /**
     * @notice Returns the full payment record for a given NFT token.
     * @param  tokenId The NFT token ID.
     */
    function getPaymentRecord(uint256 tokenId) external view returns (PaymentRecord memory) {
        require(_ownerOf(tokenId) != address(0), "SubscriptionProtocol: token does not exist");
        return paymentRecords[tokenId];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OWNER ADMIN FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Update the subscription fee.
     * @dev    Takes effect for all new payments immediately.
     * Existing active subscriptions are unaffected until renewal.
     * @param  newFee New fee in wei per period.
     */
    function setSubscriptionFee(uint256 newFee) external onlyOwner {
        require(newFee > 0, "SubscriptionProtocol: fee must be > 0");
        emit FeeUpdated(subscriptionFee, newFee);
        subscriptionFee = newFee;
    }

    /**
     * @notice Update the base URI used to construct token metadata URLs.
     * @param  newBaseURI New base URI string (e.g. a new IPFS CID folder).
     */
    function setBaseTokenURI(string calldata newBaseURI) external onlyOwner {
        baseTokenURI = newBaseURI;
    }

    /**
     * @notice Toggle soulbound mode. When soulbound, NFT transfers are blocked.
     */
    function toggleSoulbound() external onlyOwner {
        soulbound = !soulbound;
        emit SoulboundToggled(soulbound);
    }

    /**
     * @notice Pause new subscriptions and renewals.
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause the protocol.
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Withdraw all collected ETH to a specified address.
     * @param  to Recipient address.
     */
    function withdraw(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "SubscriptionProtocol: zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "SubscriptionProtocol: nothing to withdraw");
        (bool success,) = to.call{value: balance}("");
        require(success, "SubscriptionProtocol: transfer failed");
        emit Withdrawn(to, balance);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Mints a payment NFT to `to`, records its metadata, and
     * appends the token ID to the subscriber's history array.
     */
    function _mintPaymentNFT(address to, uint256 periodStart, uint256 periodEnd, uint256 periodNumber)
        internal
        returns (uint256 tokenId)
    {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        // Build token URI: baseURI + tokenId + ".json"
        string memory uri = string(abi.encodePacked(baseTokenURI, tokenId.toString(), ".json"));
        _setTokenURI(tokenId, uri);

        // Store immutable payment record
        paymentRecords[tokenId] =
            PaymentRecord({subscriber: to, periodStart: periodStart, periodEnd: periodEnd, periodNumber: periodNumber});

        subscriberTokens[to].push(tokenId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC721 OVERRIDES
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Blocks all token transfers when soulbound mode is enabled.
     * Minting (from == address(0)) is always allowed.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting; block transfers if soulbound
        if (soulbound && from != address(0)) {
            // FIXED: Replaced Unicode em-dash with standard hyphen
            revert("SubscriptionProtocol: soulbound - token is non-transferable");
        }

        return super._update(to, tokenId, auth);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FALLBACK — reject plain ETH sends
    // ─────────────────────────────────────────────────────────────────────────

    receive() external payable {
        revert("SubscriptionProtocol: use subscribe() or renewSubscription()");
    }
}
