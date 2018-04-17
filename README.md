# swift-event (仮称)

## Usage:

```swift
import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var incrementButton: UIButton!

    let count: Property<Int>
    let fizzbuzz: Observable<String>

    override func viewDidLoad() {
        super.viewDidLoad()

        count = Proprety(0)
        fizzbuzz = count.observe { observable in
            observable.compactMap { value in
                switch {
                case value % (3 * 5) == 0:
                    return "fizzbuzz"
                case value % 3 == 0:
                    return "fizz"
                case value % 5 == 0:
                    return "buzz"
                default:
                    return nil
                }
            }
        }

        count.subscribe(on: DispatchQueue.main) { [weak self] value in
            self?.countLabel.text = "pressed \(value) times!"
        }

        fizzbuzz.subscribe(on: DispatchQueue.main) { [weak self] value in
            guard let `self` = self else {
                return
            }
            let alert = UIAlertViewController(title: value,
                                              message: value,
                                              preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert)
        }
    }

    @IBAction func increment(button: UIButton) {
        count.value++
    }
}
```
