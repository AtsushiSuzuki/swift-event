//: A UIKit based Playground for presenting user interface
  
import UIKit
import PlaygroundSupport
import swift_event

class MyViewModel {
    let count: Property<Int>
    let fizzbuzz: Observable<String>

    init(_ initialValue: Int) {
        count = Property(initialValue)
        fizzbuzz = count.observe { observable in
            return observable.compactMap { value in
                if value % 15 == 0 {
                    return "fizzbuzz"
                } else if value % 3 == 0 {
                    return "fizz"
                } else if value % 5 == 0 {
                    return "bazz"
                } else {
                    return nil
                }
            }
        }
    }

    func increment() {
        count.value += 1
    }
}

class MyViewController : UIViewController {
    let viewModel = MyViewModel(0)
    var countLabel: UILabel!
    var incrementButton: UIButton!
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .white

        let countLabel = UILabel()
        countLabel.frame = CGRect(x: 150, y: 200, width: 200, height: 20)
        countLabel.textColor = .black
        view.addSubview(countLabel)
        self.countLabel = countLabel

        let incrementButton = UIButton(type: .system)
        incrementButton.frame = CGRect(x: 150, y: 300, width: 200, height: 20)
        incrementButton.setTitle("increment", for: .normal)
        incrementButton.addTarget(self,
                                  action: #selector(doIncrement),
                                  for: .primaryActionTriggered)
        self.incrementButton = incrementButton
        view.addSubview(incrementButton)

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.count.subscribe(on: .main) { [weak self] value in
            self?.countLabel.text = "clicked \(value) times!"
        }
        viewModel.fizzbuzz.subscribe(on: .main) { [weak self] value in
            guard let `self` = self else {
                return
            }
            let alert = UIAlertController(title: value,
                                          message: value,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK",
                                          style: .default))
            self.present(alert, animated: true)
        }
    }

    @objc func doIncrement() {
        viewModel.increment()
    }
}

// Present the view controller in the Live View window
PlaygroundPage.current.liveView = MyViewController()
