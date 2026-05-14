import SwiftUI
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct BottomBannerAdView: View {
    let adUnitID: String

    var body: some View {
        #if canImport(GoogleMobileAds)
        if adUnitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            AdMobBannerRepresentable(adUnitID: adUnitID)
                .frame(height: 50)
        }
        #else
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Text("GoogleMobileAds SDK not linked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 50)
            .padding(.horizontal)
        #endif
    }
}

#if canImport(GoogleMobileAds)
private struct AdMobBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String

    func makeUIViewController(context: Context) -> BannerContainerViewController {
        let controller = BannerContainerViewController()
        controller.configure(adUnitID: adUnitID)
        return controller
    }

    func updateUIViewController(_ controller: BannerContainerViewController, context: Context) {
        controller.configure(adUnitID: adUnitID)
    }
}

private final class BannerContainerViewController: UIViewController, BannerViewDelegate {
    private var bannerView: BannerView?
    private var loadedAdUnitID: String?
    private var currentAdUnitID = ""

    func configure(adUnitID: String) {
        currentAdUnitID = adUnitID
        loadBannerIfPossible()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadBannerIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let bannerView else { return }

        let targetWidth = max(view.bounds.width, 320)
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: targetWidth)
        if !isAdSizeEqualToSize(size1: bannerView.adSize, size2: adaptiveSize) {
            bannerView.adSize = adaptiveSize
            bannerView.load(Request())
        }
    }

    private func loadBannerIfPossible() {
        guard isViewLoaded else { return }

        let trimmedID = currentAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        guard loadedAdUnitID != trimmedID else { return }

        let banner: BannerView
        if let existing = bannerView {
            banner = existing
        } else {
            let initialSize = currentOrientationAnchoredAdaptiveBanner(
                width: max(view.bounds.width, 320)
            )
            banner = BannerView(adSize: initialSize)
            banner.translatesAutoresizingMaskIntoConstraints = false
            banner.delegate = self
            view.addSubview(banner)

            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                banner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            bannerView = banner
        }

        banner.adUnitID = trimmedID
        banner.rootViewController = self
        loadedAdUnitID = trimmedID
        banner.load(Request())
    }
}
#endif
