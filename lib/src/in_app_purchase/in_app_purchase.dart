import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import 'package:tictactoe/src/in_app_purchase/ad_removal.dart';
import 'package:tictactoe/src/snack_bar/snack_bar.dart';

class InAppPurchaseNotifier extends ChangeNotifier {
  static final Logger _log = Logger('InAppPurchases');

  late StreamSubscription<List<PurchaseDetails>> _subscription;

  AdRemovalPurchase _adRemoval = AdRemovalPurchase.notStarted();

  AdRemovalPurchase get adRemoval => _adRemoval;

  /// Creates a new in-app purchase [ChangeNotifier], which subscribes
  /// to the provided [purchaseStream].
  ///
  /// In production, you'll want to call this with:
  ///
  ///     final purchases =
  ///         InAppPurchaseNotifier(InAppPurchase.instance.purchaseStream);
  ///
  /// In testing, you can of course provide a mock stream.
  InAppPurchaseNotifier(Stream<List<PurchaseDetails>> purchaseStream) {
    _subscription = purchaseStream.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      _log.severe('Error occurred on the purchaseStream: $error');
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.productID != AdRemovalPurchase.productId) {
        _log.severe("The handling of the product with id "
            "'${purchaseDetails.productID}' is not implemented.");
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.pending) {
        _adRemoval = AdRemovalPurchase.pending();
        notifyListeners();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          _log.severe('Error with purchase: ${purchaseDetails.error}');
          _adRemoval = AdRemovalPurchase.error(purchaseDetails.error!);
          notifyListeners();
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            _adRemoval = AdRemovalPurchase.active();
            if (purchaseDetails.status == PurchaseStatus.purchased) {
              showSnackBar('Thank you for your support!');
            }
            notifyListeners();
          } else {
            _log.severe('Purchase verification failed: $purchaseDetails');
            _adRemoval = AdRemovalPurchase.error(
                StateError('Purchase could not be verified'));
            notifyListeners();
          }
        }
        if (purchaseDetails.pendingCompletePurchase) {
          // Confirm purchase back to the store.
          await InAppPurchase.instance.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    _log.info('Verifying purchase: ${purchaseDetails.verificationData}');
    // TODO: verify the purchase.
    // See the info in [purchaseDetails.verificationData] to learn more.
    // There's also a codelab that explains purchase verification
    // on the backend:
    // https://codelabs.developers.google.com/codelabs/flutter-in-app-purchases#9
    return true;
  }

  void _reportError(String message) {
    _log.severe(message);
    showSnackBar(message);
    _adRemoval = AdRemovalPurchase.error(message);
    notifyListeners();
  }

  Future<void> buy() async {
    if (!await InAppPurchase.instance.isAvailable()) {
      _reportError('InAppPurchase.instance not available');
      return;
    }

    _log.info('Querying the store with queryProductDetails()');
    final response = await InAppPurchase.instance
        .queryProductDetails({AdRemovalPurchase.productId});

    if (response.error != null) {
      _reportError('There was an error when making the purchase: '
          '${response.error}');
      return;
    }

    if (response.productDetails.length != 1) {
      _reportError('There was an error when making the purchase: '
          'product ${AdRemovalPurchase.productId} does not exist.');
      response.productDetails
          .map((e) => '${e.id}: ${e.title}')
          .forEach(_log.info);
      return;
    }
    final productDetails = response.productDetails.single;

    _log.info('Making the purchase');
    final purchaseParam = PurchaseParam(productDetails: productDetails);
    final success = await InAppPurchase.instance
        .buyNonConsumable(purchaseParam: purchaseParam);
    _log.info('buyNonConsumable() request was sent with success: $success');
    // The result of the purchase will be reported in the purchaseStream,
    // which is handled in [_listenToPurchaseUpdated].
  }
}