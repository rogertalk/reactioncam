import AlamofireImage

struct AspectScaledToFillSizeBiasedFilter: ImageFilter, Sizable {
    let bias: CGPoint

    var filter: (Image) -> Image {
        return { image in
            let size = self.size
            guard size.width * size.height > 0 else { return image }
            let ratio = size.width / size.height
            let imageRatio = image.size.width / image.size.height
            let factor = imageRatio > ratio ? size.height / image.size.height : size.width / image.size.width
            let scaledSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            let origin = CGPoint(x: (size.width - scaledSize.width) * self.bias.x,
                                 y: (size.height - scaledSize.height) * self.bias.y)
            UIGraphicsBeginImageContextWithOptions(size, true, 0)
            let context = UIGraphicsGetCurrentContext()!
            defer { UIGraphicsEndImageContext() }
            context.interpolationQuality = .high
            image.draw(in: CGRect(origin: origin, size: scaledSize))
            return UIGraphicsGetImageFromCurrentImageContext()!
        }
    }

    var size: CGSize {
        guard let view = self.view else { return .zero }
        if Thread.isMainThread { return view.bounds.size }
        var size = CGSize.zero
        DispatchQueue.main.sync {
            size = view.bounds.size
        }
        return size
    }

    private(set) weak var view: UIView?

    init(view: UIView, biasX x: CGFloat, y: CGFloat) {
        self.bias = CGPoint(x: x, y: y)
        self.view = view
    }
}
