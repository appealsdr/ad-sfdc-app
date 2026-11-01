/**
 * Lightning App Builder datasource for amazonSellerCard's "Seller Field"
 * property. Defaults to the seller page URL, then storefront link, then Seller ID.
 */
global class AmazonSellerFieldPicklist extends RecordTextFieldPicklist {

    global AmazonSellerFieldPicklist(VisualEditor.DesignTimePageContext context) {
        super(context);
    }

    global override List<String> defaultFieldPatterns() {
        return new List<String>{ 'seller.?page', 'storefront', 'seller.?id', 'amazon' };
    }
}