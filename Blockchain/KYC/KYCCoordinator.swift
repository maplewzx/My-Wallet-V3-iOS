//
//  KYCCoordinator.swift
//  Blockchain
//
//  Created by Chris Arriola on 7/27/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift

enum KYCEvent {

    /// When a particular screen appears, we need to
    /// look at the `NabuUser` object and determine if
    /// there is data there for pre-populate the screen with.
    case pageWillAppear(KYCPageType)

    /// This will push on the next page in the KYC flow.
    case nextPageFromPageType(KYCPageType, KYCPagePayload?)

    /// Event emitted when the provided page type emits an error
    case failurePageForPageType(KYCPageType, KYCPageError)
}

protocol KYCCoordinatorDelegate: class {
    func apply(model: KYCPageModel)
}

/// Coordinates the KYC flow. This component can be used to start a new KYC flow, or if
/// the user drops off mid-KYC and decides to continue through it again, the coordinator
/// will handle recovering where they left off.
@objc class KYCCoordinator: NSObject, Coordinator {

    // MARK: - Public Properties

    weak var delegate: KYCCoordinatorDelegate?

    static let shared = KYCCoordinator()

    @objc class func sharedInstance() -> KYCCoordinator {
        return KYCCoordinator.shared
    }

    // MARK: - Private Properties

    private(set) var user: NabuUser?

    private(set) var country: KYCCountry?

    private weak var rootViewController: UIViewController?

    fileprivate var navController: KYCOnboardingNavigationController!

    private let pageFactory = KYCPageViewFactory()

    private let disposables = CompositeDisposable()

    private override init() { /* Disallow initializing from outside objects */ }

    deinit {
        disposables.dispose()
    }

    // MARK: Public

    func start() {
        guard let rootViewController = UIApplication.shared.keyWindow?.rootViewController else {
            Logger.shared.warning("Cannot start KYC. rootViewController is nil.")
            return
        }
        start(from: rootViewController)
    }

    @objc func start(from viewController: UIViewController) {
        rootViewController = viewController
        LoadingViewPresenter.shared.showBusyView(withLoadingText: LocalizationConstants.loading)
        let disposable = BlockchainDataRepository.shared.fetchNabuUser()
            .subscribeOn(MainScheduler.asyncInstance)
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [unowned self] in
                Logger.shared.debug("Got user with ID: \($0.personalDetails?.identifier ?? "")")
                LoadingViewPresenter.shared.hideBusyView()
                self.user = $0
                if self.pageTypeForUser() == .accountStatus {
                    self.presentAccountStatusView(for: $0.status, in: viewController)
                } else {
                    self.initializeNavigationStack(viewController)
                    self.restoreToMostRecentPageIfNeeded()
                }
            }, onError: { error in
                Logger.shared.error("Failed to get user: \(error.localizedDescription)")
                LoadingViewPresenter.shared.hideBusyView()
                AlertViewPresenter.shared.standardError(message: LocalizationConstants.Errors.genericError)
            })
         _ = disposables.insert(disposable)
    }

    func finish() {
        // TODO: if applicable, persist state, do housekeeping, etc...
        if navController == nil { return }
        navController.dismiss(animated: true)
    }

    func handle(event: KYCEvent) {
        switch event {
        case .pageWillAppear(let type):
            handlePageWillAppear(for: type)
        case .failurePageForPageType(_, let error):
            handleFailurePage(for: error)
        case .nextPageFromPageType(let type, let payload):
            handlePayloadFromPageType(type, payload)
            guard let nextPage = type.nextPage(for: self.user, country: self.country) else { return }
            let controller = pageFactory.createFrom(
                pageType: nextPage,
                in: self,
                payload: payload
            )
            controller.navigationItem.hidesBackButton = (nextPage == .applicationComplete)
            navController.pushViewController(controller, animated: true)
        }
    }

    func presentAccountStatusView(for status: KYCAccountStatus, in viewController: UIViewController) {
        let accountStatusViewController = KYCInformationController.make(with: self)
        accountStatusViewController.viewModel = KYCInformationViewModel.create(for: status)
        accountStatusViewController.viewConfig = KYCInformationViewConfig.create(for: status)
        accountStatusViewController.primaryButtonAction = { viewController in
            switch status {
            case .approved:
                viewController.dismiss(animated: true) {
                    guard let viewController = self.rootViewController else {
                        Logger.shared.error("View controller to present on is nil.")
                        return
                    }
                    ExchangeCoordinator.shared.start(rootViewController: viewController)
                }
            case .pending:
                PushNotificationManager.shared.requestAuthorization()
            case .failed, .expired:
                // Confirm with design that this is how we should handle this
                URL(string: Constants.Url.blockchainSupport)?.launch()
            case .none, .underReview: return
            }
        }
        presentInNavigationController(accountStatusViewController, in: viewController)
    }

    // MARK: View Restoration

    /// Restores the user to the most recent page if they dropped off mid-flow while KYC'ing
    private func restoreToMostRecentPageIfNeeded() {
        let startingPage = KYCPageType.welcome
        let endPage = pageTypeForUser()
        var currentPage = startingPage
        while currentPage != endPage {
            guard let nextPage = currentPage.nextPage(for: user, country: country) else { return }

            currentPage = nextPage

            let nextController = pageFactory.createFrom(
                pageType: currentPage,
                in: self
            )
            navController.pushViewController(nextController, animated: false)
        }
    }

    private func initializeNavigationStack(_ viewController: UIViewController) {
        guard let welcomeViewController = pageFactory.createFrom(
            pageType: .welcome,
            in: self
        ) as? KYCWelcomeController else { return }
        navController = presentInNavigationController(welcomeViewController, in: viewController)
    }

    // MARK: Private Methods

    private func handlePayloadFromPageType(_ pageType: KYCPageType, _ payload: KYCPagePayload?) {
        guard let payload = payload else { return }
        switch payload {
        case .countrySelected(let country):
            self.country = country
        case .phoneNumberUpdated:
            // Not handled here
            return
        }
    }

    private func handleFailurePage(for error: KYCPageError) {

        let informationViewController = KYCInformationController.make(with: self)
        informationViewController.viewConfig = KYCInformationViewConfig(
            titleColor: UIColor.gray5,
            isPrimaryButtonEnabled: true
        )

        switch error {
        case .countryNotSupported(let country):
            informationViewController.viewModel = KYCInformationViewModel.createForUnsupportedCountry(country)
            informationViewController.primaryButtonAction = { [unowned self] viewController in
                viewController.presentingViewController?.presentingViewController?.dismiss(animated: true)
                let interactor = KYCCountrySelectionInteractor()
                let disposable = interactor.selected(
                    country: country,
                    shouldBeNotifiedWhenAvailable: true
                )
                self.disposables.insertWithDiscardableResult(disposable)
            }
            presentInNavigationController(informationViewController, in: navController)
        case .stateNotSupported(let state):
            informationViewController.viewModel = KYCInformationViewModel.createForUnsupportedState(state)
            informationViewController.primaryButtonAction = { [unowned self] viewController in
                viewController.presentingViewController?.presentingViewController?.dismiss(animated: true)
                let interactor = KYCCountrySelectionInteractor()
                let disposable = interactor.selected(
                    state: state,
                    shouldBeNotifiedWhenAvailable: true
                )
                self.disposables.insertWithDiscardableResult(disposable)
            }
            presentInNavigationController(informationViewController, in: navController)
        }
    }

    private func handlePageWillAppear(for type: KYCPageType) {
        switch type {
        case .welcome,
             .country,
             .states,
             .accountStatus,
             .applicationComplete:
            break
        case .profile:
            guard let current = user else { return }
            delegate?.apply(model: .personalDetails(current))
        case .address:
            guard let current = user else { return }
            delegate?.apply(model: .address(current, country))
        case .enterPhone, .confirmPhone:
            guard let current = user else { return }
            delegate?.apply(model: .phone(current))
        case .verifyIdentity:
            guard let countryCode = country?.code ?? user?.address?.countryCode else { return }
            delegate?.apply(model: .verifyIdentity(countryCode: countryCode))
        }
    }

    @discardableResult private func presentInNavigationController(
        _ viewController: UIViewController,
        in presentingViewController: UIViewController
    ) -> KYCOnboardingNavigationController {
        let navController = KYCOnboardingNavigationController.make()
        navController.pushViewController(viewController, animated: false)
        navController.modalTransitionStyle = .coverVertical
        presentingViewController.present(navController, animated: true)
        return navController
    }

    private func pageTypeForUser() -> KYCPageType {
        guard let currentUser = user else { return .welcome }

        guard let personalDetails = currentUser.personalDetails, personalDetails.firstName != nil else {
            return .welcome
        }

        guard currentUser.address != nil else { return .country }

        guard currentUser.mobile != nil else { return .enterPhone }

        guard currentUser.status != .none else { return .verifyIdentity }

        return .accountStatus
    }
}
