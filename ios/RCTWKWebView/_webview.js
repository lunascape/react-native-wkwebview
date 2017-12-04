function sendToHost(channel, data) {
  var message = {
    'type':channel,
    'data': data
  }
  window.webkit.messageHandlers.reactNative.postMessage(message);
};

var _enableDefualtContextmenu = true;
var _contextMenuListenerCount = 0;
var _lastClickedX = -1;
var _lastClickedY = -1;
var _loginInputs = [];

__preload = {
  findLoginForm: function() {
    var forms = document.getElementsByTagName('form');
    _loginInputs = [];

    for(var i = 0; i < forms.length; i++) {
      var form = forms.item(i);
      var inputs = form.getElementsByTagName('input');
      var accountFields = [];
      var passFields = [];
      for(var j = 0; j < inputs.length; j++) {
        var input = inputs.item(j);
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
        var accountField = accountFields[0];
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
    sendToHost('loginForm', {'exist':_loginInputs.length > 0});
  },
  fillPassForm: function(account, password) {
    for(var i = 0; i < _loginInputs.length; i++) {
      _inputAccount = _loginInputs[i]['account'];
      _inputPassword = _loginInputs[i]['password'];
      _inputAccount.value = account;
      _inputPassword.value = password;
    }
  },
  observeSubmit: function() {
    for(var i = 0; i < _loginInputs.length; i++) {
      var form = _loginInputs[i]['form'];
      form.addEventListener('submit', function(e) {
        var inputs = form.getElementsByTagName('input');
        var passFieldExist = false;
        var password = '';
        var account = '';
        for(var j = 0; j < inputs.length; j++) {
          var input = inputs.item(j);
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

// We're using a global variable to store the number of occurrences
var MyApp_SearchResultCount = 0;

// helper function, recursively searches in elements and their child nodes
function MyApp_HighlightAllOccurencesOfStringForElement(element,keyword,color,doc) {
    if (element) {
        if (element.nodeType == 3) {        // Text node
            while (true) {
                var value = element.nodeValue;  // Search for keyword in text node
                var idx = value.toLowerCase().indexOf(keyword);

                if (idx < 0) break;             // not found, abort

                var span = doc.createElement("span");
                var text = doc.createTextNode(value.substr(idx,keyword.length));
                span.appendChild(text);
                span.setAttribute("class","MyAppHighlight");
                span.setAttribute("name","MyAppHighlight");
                span.style.backgroundColor=color;
                span.style.color="black";
                text = doc.createTextNode(value.substr(idx+keyword.length));
                element.deleteData(idx, value.length - idx);
                var next = element.nextSibling;
                element.parentNode.insertBefore(span, next);
                element.parentNode.insertBefore(text, next);
                element = text;
                MyApp_SearchResultCount++;    // update the counter
            }
        } else if ((element.nodeType == 1)&&(element.tagName.toLowerCase() == "iframe")&&(element.contentDocument != null)) {
            //alert("iframe: " + element.contentDocument.body.outerHTML);
            if (element.style.display != "none" && element.nodeName.toLowerCase() != 'select' && element.nodeName.toLowerCase() != 'script') {
                MyApp_HighlightAllOccurencesOfStringForElement(element.contentDocument.body,keyword,color,element.contentDocument);
            }
        } else if (element.nodeType == 1) { // Element node
            //if (element.style.display != "none" && element.nodeName.toLowerCase() != 'select') {
            if (element.style.display != "none" && element.nodeName.toLowerCase() != 'select' && element.nodeName.toLowerCase() != 'script') {
                for (var i=element.childNodes.length-1; i>=0; i--) {
                    MyApp_HighlightAllOccurencesOfStringForElement(element.childNodes[i],keyword,color,doc);
                }
            }
        }
    }
}


// the main entry point to start the search
function MyApp_HighlightAllOccurencesOfString(keyword,color) {
    //MyApp_RemoveAllHighlights();
    MyApp_HighlightAllOccurencesOfStringForElement(document.body, keyword.toLowerCase(), color, document);

    //    var nodes = document.getElementsByTagName('iframe');
    //    alert("iframe count: " + nodes.length);
    //    for (var i=0; i<nodes.length; i++) {
    //        if (nodes[i].contentDocument != null) {
    //            alert("iframe: " + nodes[i].contentDocument.body.outerHTML);
    //            MyApp_HighlightAllOccurencesOfStringForElement(nodes[i].contentDocument.body, keyword.toLowerCase(), nodes[i].contentDocument);
    //        } else {
    //            alert("iframe contentDocument: null");
    //        }
    //    }
}

function MyApp_ScrollToHighlightTop() {
    // scroll
    var offset = cumulativeOffsetTop(document.getElementsByName("MyAppHighlight")[0]);
    //alert('offset: ' + offset);
    window.scrollTo(0,offset);
    //window.scrollTo(0,document.getElementsByName("MyAppHighlight")[0].offsetTop);
    //alert('offset: ' + document.getElementsByName("MyAppHighlight")[0].offsetTop);
}

// helper function, recursively removes the highlights in elements and their childs
function MyApp_RemoveAllHighlightsForElement(element) {
    if (element) {
        if ((element.nodeType == 1)&&(element.tagName.toLowerCase() == "iframe")&&(element.contentDocument != null)) {
            MyApp_RemoveAllHighlightsForElement(element.contentDocument.body);
        } else if (element.nodeType == 1) {
            if (element.getAttribute("class") == "MyAppHighlight") {
                var text = element.removeChild(element.firstChild);
                element.parentNode.insertBefore(text,element);
                element.parentNode.removeChild(element);
                return true;
            } else {
                var normalize = false;
                for (var i=element.childNodes.length-1; i>=0; i--) {
                    if (MyApp_RemoveAllHighlightsForElement(element.childNodes[i])) {
                        normalize = true;
                    }
                }
                if (normalize) {
                    element.normalize();
                }
            }
        }
    }
    return false;
}

// the main entry point to remove the highlights
function MyApp_RemoveAllHighlights() {
    MyApp_SearchResultCount = 0;
    MyApp_RemoveAllHighlightsForElement(document.body);
}


//参考：http://d.hatena.ne.jp/susie-t/20061004/1159942798
function cumulativeOffsetTop(element) {
    var valueT = 0;
    do {
        valueT += element.offsetTop  || 0;
        element = element.offsetParent;
    } while (element);
    return valueT;
}

