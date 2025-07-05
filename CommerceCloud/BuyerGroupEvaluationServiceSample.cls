/**
 * BuyerGroupEvaluationServiceSample is a sample implementation of the BuyerGroupEvaluationService used to determine buyer group IDs for a user (guest or logged-in).
 * The use case for this sample implementation is as follows:
 * - Out-of-the-box buyer groups based on account, market, and data cloud segment should be returned for both logged-in and guest users.
 * - In addition, for logged-in users, the buyer groups associated with the ContactPointAddress.Country of the Contact linked to the user are also returned.
 * 
 * No Data model changes are required.
 * 
 * Important considerations in the code below:
 * - Buyer group responses should be cached using Org Cache to support low latency. 
 * - No more than MAX_BUYER_GROUPS should be returned by the code. 
 */
public without sharing class BuyerGroupEvaluationServiceSample extends commercebuygrp.BuyerGroupEvaluationService {

    private static Integer MAX_BUYER_GROUPS = 30;

    public override commercebuygrp.BuyerGroupResponse getBuyerGroupIds(commercebuygrp.BuyerGroupRequest request) {
        String currentUserId = UserInfo.getUserId(); // Gets the current user ID; could be a logged-in or guest user
        String webstoreId = request.getStoreId(); // Gets the webstore record ID
        String accountId = request.getAccountId(); // Gets the account ID of the user
        String siteId = ((String) [SELECT SiteId FROM WebstoreNetwork WHERE WebstoreId = :webstoreId][0].get('SiteId')).substring(0, 15); // Gets the network site ID
        Map<String, Object> requestParameters = request.getRequestContextParameters();
        Boolean isGuestUser = (Boolean) requestParameters.get('isGuestUser');
        String guestUUIDKey = 'guest_uuid_essential_' + siteId; // Gets the guest UUID cookie key for the current webstore
        String deviceId  = (String) requestParameters.get(guestUUIDKey); // Gets the guest UUID cookie value for the current user and webstore
        
        String shippingCountryCode;
        // If the user is logged in, get the ContactPointAddress.Country
        if (!isGuestUser) {
            SObject defaultContactPointAddress = [SELECT Country FROM ContactPointAddress
                                                  WHERE AddressType = 'Shipping' AND IsDefault = true AND OwnerId = :currentUserId][0];
            shippingCountryCode = (String) defaultContactPointAddress.get('Country');
        }
        
        String cachePartition = 'local.BuyerGroup';
        Cache.OrgPartition orgPartition = Cache.Org.getPartition(cachePartition); // Gets the buyer group org cache partition
        
        // Cache key must be alphanumeric; converting currentUserId+shippingCountryCode and deviceId to a hashed key
        String cacheKey = EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(isGuestUser ? deviceId : currentUserId + '-' + shippingCountryCode))
        );
        if (orgPartition.contains(cacheKey)) {
            // Cache hit — return cached buyer groups
            return new commercebuygrp.BuyerGroupResponse((Set<String>) orgPartition.get(cacheKey));  
        }

        // Getting default out-of-the-box buyer groups based on existing logic: account, market, and data cloud segment-based buyer groups
        commercebuygrp.BuyerGroupResponse defaultBuyerGroupResponse = super.getBuyerGroupIds(request);
        Set<String> buyerGroupIds = new Set<String>(defaultBuyerGroupResponse.getBuyerGroupIds());

        Set<String> validCountries = new Set<String>();

        // If the user is logged in, look for buyer groups that matches the valid countries
        if (!isGuestUser) {
            if (shippingCountryCode != null) {
                validCountries.add(shippingCountryCode);
            }
            // In this use case, the Buyer Group names are equivalent to the Country codes
            for (BuyerGroup buyerGroup : [SELECT Id, Name FROM BuyerGroup WHERE Name IN :validCountries]) {
                buyerGroupIds.add(buyerGroup.Id);
            }
        }

        // Buyer group extensibility supports only up to MAX_BUYER_GROUPS buyer groups
        if (buyerGroupIds.size() > MAX_BUYER_GROUPS) {
            commercebuygrp.BuyerGroupResponse response = new commercebuygrp.BuyerGroupResponse();
            String errorMessage = 'More than ' + MAX_BUYER_GROUPS + ' buyer groups retrieved for the user. Contact Store Administrator.';
            response.setError(errorMessage, errorMessage);
            return response;
        }

        orgPartition.put(cacheKey, buyerGroupIds);
        return new commercebuygrp.BuyerGroupResponse(buyerGroupIds);
    }
}