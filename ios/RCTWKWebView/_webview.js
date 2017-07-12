function sendToHost(channel, data) {
  let message = {
    'channel':channel,
    'data': data
  }
  window.webkit.messageHandlers.observe.postMessage(message);
};

var _enableDefualtContextmenu = true;
var _contextMenuListenerCount = 0;
var _lastClickedX = -1;
var _lastClickedY = -1;
var _loginInputs = [];

__preload = {
  findLoginForm: function() {
    let forms = document.getElementsByTagName('form');
    _loginInputs = [];

    for(let i = 0; i < forms.length; i++) {
      let form = forms.item(i);
      let inputs = form.getElementsByTagName('input');
      var accountFields = [];
      var passFields = [];
      for(let j = 0; j < inputs.length; j++) {
        let input = inputs.item(j);
        if (!(input.type === 'password' || input.type === 'text' || input.type === 'email')) {
          continue;
        }
        if (input.type === 'password') {
          passFields.push(input);
        } else if (passFields.length === 0) {
          // Account field commonly put above password field
          accountFields.push(input);
        }
      }
      // A login should has only 1 password field and 1 account field before password
      if (passFields.length === 1 && accountFields.length === 1) {
        let accountField = accountFields[0];
        accountField.addEventListener('dblclick', function(e) {
        sendToHost('selectAccount', {'account': e.target.value, 'position':{'x':e.target.x, 'y':e.target.y}});
        });
        accountField.addEventListener('keydown', function(e) {
        if (e.keyCode === 40) {
            console.log('Should send selectAccount event');
        }
        });
        _loginInputs.push({'form':form, 'account': accountField, 'password':passFields[0]});
      }
    }
    return(_loginInputs.length > 0);
  },
  fillPassForm: function(account, password) {
    for(let i = 0; i < _loginInputs.length; i++) {
      _inputAccount = _loginInputs[i]['account'];
      _inputPassword = _loginInputs[i]['password'];
      _inputAccount.value = account;
      _inputPassword.value = password;
    }
  },
  observeSubmit: function() {
    for(let i = 0; i < _loginInputs.length; i++) {
      let form = _loginInputs[i]['form'];
      form.addEventListener('submit', function(e) {
        let inputs = form.getElementsByTagName('input');
        var passFieldExist = false;
        var password = '';
        var account = '';
        for(let j = 0; j < inputs.length; j++) {
          let input = inputs.item(j);
          if (!(input.type === 'password' || input.type === 'text' || input.type === 'email')) {
            continue;
          }
          if (input.type === 'password') {
            if (passFieldExist) {
              //A signup form normally has 2 password fields
              //--> Don't need to save password when signup
              passFieldExist = false;
              break;
            }
            passFieldExist = true;
            password = input.value.trim();
          } else if (!passFieldExist){
            account = input.value.trim();
          }
        }
        if (passFieldExist && account.length && password.length) {
          sendToHost('loginData', {'account': account, 'password': password});
        }
      });
    }
  }
}
