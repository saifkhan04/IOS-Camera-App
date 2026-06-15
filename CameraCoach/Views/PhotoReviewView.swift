// PhotoReviewView.swift
// Full-screen review of the last shot, shown when the shooter taps the corner
// gallery thumbnail. iOS has no public way to deep-link the system Photos app to
// a specific asset, so we show the captured image in-app (decoded from the bytes
// we already have) and offer "Open in Photos" as a hand-off to the full library.

import SwiftUI

struct PhotoReviewView: View {

    // The encoded HEIF/JPEG bytes of the most recent capture. Decoded here for
    // display — kept as Data (small) rather than a full decoded UIImage (~tens
    // of MB) so we're not holding a big bitmap resident between views.
    let imageData: Data
    var onOpenInPhotos: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                Text("Couldn’t load the photo")
                    .foregroundColor(.white.opacity(0.7))
            }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                Button(action: onOpenInPhotos) {
                    Label("Open in Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(.bottom, 32)
            }
        }
    }
}
