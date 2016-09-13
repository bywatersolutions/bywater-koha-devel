var React = require('react');
var ReactDOM = require('react-dom');

var ItemMessages = React.createClass({
    propTypes: {
        messages: React.PropTypes.array.isRequired
    },
    getInitialState: function() {
        return { messages: this.props.messages };
    },
    addMessage: function(message) {
        this.setState(function(state) {
            var newData = state.messages.slice();
            newData.push( message );
            return {messages: newData};
        });
    },
    removeMessage: function(index) {
        this.setState(function(state) {
            var newData = state.messages.slice();
            newData.splice(index, 1);
            return {messages: newData};
        });
    },
    render: function () {
        var item_messages = this;
        return  <div className="listgroup">
                    <h4>Messages</h4>
                    <ol className="bibliodetails">
                        {this.state.messages.map(function(message, index) {
                            return <ItemMessage key={message.id} message={message} index={index} onRemove={item_messages.removeMessage} />
                        })}
                        <ItemMessageCreator onAdd={item_messages.addMessage}/>
                    </ol>
                </div>;
    }
});

var ItemMessage = React.createClass({
    propTypes: {
        message: React.PropTypes.object.isRequired,
        index: React.PropTypes.number.isRequired,
        onRemove: React.PropTypes.func.isRequired,
    },
    removeMessage: function() {
        if ( confirm("Delete message the following message? : " + this.props.message.content ) ) {
            this.props.onRemove(this.props.index);
        }
    },
    render: function () {
        return  <li>
                    <span className="label">
                        <i className="fa fa-minus-circle" onClick={this.removeMessage}></i>
                        {this.props.message.type}
                    </span>
                    {this.props.message.content}
                </li>
      }
});

var ItemMessageCreator = React.createClass({
    propTypes: {
        onAdd: React.PropTypes.func.isRequired,
    },
    getInitialState: function () {
        return {
            content: "",
            type: "",
        };
    },
    addMessage: function() {
        this.props.onAdd(
            {
                id: Math.random() * 100,
                type: this.state.type,
                content: this.state.content,
            }
        );
    },
    cancelMessage: function() {
        this.setState( this.getInitialState );
        return false;
    },
    handleTypeChange: function(e) {
        this.setState({ type: e.target.value });
    },
    handleContentChange: function(e) {
        this.setState({ content: e.target.value });
    },
    render: function () {
        return  <li>
                    <span className="label">
                        <select value={this.state.type} onChange={this.handleTypeChange}>
                            <option value="test1">Test 1</option>
                            <option value="test2">Test 2</option>
                            <option value="test3">Test 3</option>
                        </select>
                    </span>
                    <input className="input-xlarge" type="text" value={this.state.content} onChange={this.handleContentChange} />
                    <button className="submit" onClick={this.addMessage}>
                        <i className="fa fa-plus-circle"></i>
                        Add message
                    </button>
                    <a href="javascript:void(0);" onClick={this.cancelMessage}>Cancel</a>
                </li>
      }
});

$( document ).ready(function() {
    var messages = [
        { id: 1, type: "Test 1", content: "Message 1" },
        { id: 2, type: "Test 2", content: "Message 2" },
        { id: 3, type: "Test 3", content: "Message 3" },
        { id: 4, type: "Test 4", content: "Message 4" },
        { id: 5, type: "Test 5", content: "Message 5" },
    ];

    $('.item-messages').each(function() {
        ReactDOM.render(
            <ItemMessages messages={messages}/>,
            this
        );
    });
});
