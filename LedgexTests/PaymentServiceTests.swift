
import XCTest
@testable import Ledgex

class PaymentServiceTests: XCTestCase {

    var paymentService: PaymentService!

    override func setUp() {
        super.setUp()
        paymentService = PaymentService.shared
    }

    override func tearDown() {
        paymentService = nil
        super.tearDown()
    }

    // MARK: - Provider Availability

    func testProviderAvailability() {
        // This test will depend on the apps installed on the simulator/device.
        // For CI, it's better to mock UIApplication.shared.canOpenURL.
        // For now, we just print the availability.
        print("Apple Pay available: \(paymentService.isProviderAvailable(.applePay))")
        print("Venmo available: \(paymentService.isProviderAvailable(.venmo))")
        print("PayPal available: \(paymentService.isProviderAvailable(.paypal))")
        print("Zelle available: \(paymentService.isProviderAvailable(.zelle))")
        print("Cash App available: \(paymentService.isProviderAvailable(.cashApp))")
    }

    // MARK: - Deep Link Generation

    func testVenmoURLGeneration() {
        let from = Person(name: "User A")
        let to = Person(name: "User B")
        let settlement = Settlement(from: from, to: to, amount: 10.0)
        let recipientAccount = LinkedPaymentAccount(provider: .venmo, accountIdentifier: "user-b")

        let expectation = XCTestExpectation(description: "Venmo URL is generated")

        Task {
            let result = await paymentService.processVenmoPayment(settlement: settlement, recipientAccount: recipientAccount)
            // This will attempt to open the URL, so we can't check the URL directly.
            // We will just check if the result is success, which means the URL was generated and opened.
            // In a real test environment, we would mock UIApplication.shared.open.
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testZelleURLGeneration() {
        let from = Person(name: "User A")
        let to = Person(name: "User B")
        let settlement = Settlement(from: from, to: to, amount: 15.0)
        let recipientAccount = LinkedPaymentAccount(provider: .zelle, accountIdentifier: "user.b@example.com")

        let expectation = XCTestExpectation(description: "Zelle URL is generated")

        Task {
            let result = await paymentService.processZellePayment(settlement: settlement, recipientAccount: recipientAccount)
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testCashAppURLGeneration() {
        let from = Person(name: "User A")
        let to = Person(name: "User B")
        let settlement = Settlement(from: from, to: to, amount: 20.0)
        let recipientAccount = LinkedPaymentAccount(provider: .cashApp, accountIdentifier: "$userb")

        let expectation = XCTestExpectation(description: "Cash App URL is generated")

        Task {
            let result = await paymentService.processCashAppPayment(settlement: settlement, recipientAccount: recipientAccount)
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testPayPalURLGeneration() {
        let from = Person(name: "User A")
        let to = Person(name: "User B")
        let settlement = Settlement(from: from, to: to, amount: 25.0)
        let recipientAccount = LinkedPaymentAccount(provider: .paypal, accountIdentifier: "user-b")

        let expectation = XCTestExpectation(description: "PayPal URL is generated")

        Task {
            let result = await paymentService.processPayPalPayment(settlement: settlement, recipientAccount: recipientAccount)
            XCTAssertTrue(result.success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Manual Testing Notes

    func testManualAndUITesting() {
        XCTFail("""
        The following need to be tested manually or with UI tests:
        - Apple Pay flow
        - Deep link opening and payment completion in Venmo, Zelle, Cash App, and PayPal
        - Error handling for when payment apps are not installed
        - User cancellation flow in payment apps
        """)
    }
}
