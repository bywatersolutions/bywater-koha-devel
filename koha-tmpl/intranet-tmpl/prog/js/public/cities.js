var React = require('react');
var ReactDOM = require('react-dom');
var BootstrapTable = require('react-bootstrap-table').BootstrapTable;
var TableHeaderColumn = require('react-bootstrap-table').TableHeaderColumn;

var CitiesEditor = React.createClass({
    getInitialState: function() {
        return {
            show_form: false,
            selected_row: undefined,
            cities: []
        };
    },

    componentDidMount: function() {
        console.log("componentDidMount");
        this.serverRequest = $.get('/api/v1/cities', function (result) {
            this.setCities(result);
        }.bind(this));
    },

    render: function() {
        return <span>
            <CitiesToolbar
                showCityForm={this.handleShowCityForm}
                deleteCity={this.handleDeleteCity}
            />
            { this.state.show_form ?
                <CitiesForm hideCityForm={this.handleHideCityForm} createOrUpdateCity={this.handleCreateOrUpdateCity} />
                :
                <CitiesTable ref="citiesTable" cities={this.state.cities} setSelectedRow={this.handleSetSelectedRow}/>
            }
        </span>
    },

    // FIXME: I believe there is a react hook for setting state, we should use that instead
    setCities: function( cities ) {
        this.setState({
            cities: cities
        });
        if( this.refs.citiesTable ){
            this.refs.citiesTable.setState({
                cities: cities
            });
        }
    },

    handleShowCityForm: function() {
        this.setState({
            show_form: true
        });
    },

    handleHideCityForm: function() {
        this.setState({
            show_form: false
        });
    },

    handleSetSelectedRow( row ) {
        this.setState({
            selected_row: row
        })
    },

    handleDeleteCity() {
        let myself = this;
        if (this.state.selected_row) {
            let cityid = this.state.selected_row.cityid;
            $.delete('/api/v1/cities/' + cityid, function (result) {
                let current_cities = this.state.cities;
                let index = current_cities.map(function(x) {return x.cityid; }).indexOf(cityid);
                console.log("INDEX");
                console.log(index);
                current_cities.splice(index, 1);
                this.setCities(current_cities);
            }.bind(this));
        }
    },

    handleCreateOrUpdateCity: function(city) {
        let myself = this;
        city.blah = 'asdf';
        $.post({
            url: '/api/v1/cities',
            data: JSON.stringify(city),
            success: function(data) { // We get back the same city, now with an id
                console.log("NEW CITY3");
                console.log(data);
                var current_cities = myself.state.cities;
                current_cities.push(data);
                myself.setCities(current_cities);
                myself.handleHideCityForm();
            },
        }).bind(this);
    }
});

var CitiesTable = React.createClass({
    getInitialState: function() {
        return {
            cities: this.props.cities
        };
    },

    render: function() {
        var myself = this;

        return  <span>
            { this.state.cities.length ?
                <span>
                <BootstrapTable
                  search={true}
                  pagination={true}
                  selectRow={ { mode:'radio', onSelect:this.onRowSelect } }
                  data={this.state.cities}
                >
                    <TableHeaderColumn dataField="cityid" isKey={true}>City ID</TableHeaderColumn>
                    <TableHeaderColumn dataField="city_name">Name</TableHeaderColumn>
                    <TableHeaderColumn dataField="city_state">State</TableHeaderColumn>
                    <TableHeaderColumn dataField="city_zipcode">Postal code</TableHeaderColumn>
                    <TableHeaderColumn dataField="city_country">Country</TableHeaderColumn>
                </BootstrapTable>
                <table>
                    <thead>
                        <tr>
                            <th>City ID</th>
                            <th>Name</th>
                            <th>State</th>
                            <th>Postal code</th>
                            <th>Country</th>
                            <th>&nbsp;</th>
                        </tr>
                    </thead>
                    <tbody>
                        {this.state.cities.map(function( city, index ) {
                            return <CitiesTableRow
                                key={city.cityid}
                                index={index}
                                city={city}
                                onDelete={myself.deleteCity}
                            />
                        })}
                    </tbody>
                </table>
                </span>
                : // else there are no cities to show in a table
                <span>There are no cities</span>
            }
        </span>
    },

    onRowSelect: function(row, isSelected, event) {
        this.props.setSelectedRow( row );
    },
});

var CitiesTableRow = React.createClass({
    render: function() {
        return <tr>
                    <td>{this.props.city.cityid}</td>
                    <td>{this.props.city.city_name}</td>
                    <td>{this.props.city.city_state}</td>
                    <td>{this.props.city.city_zipcode}</td>
                    <td>{this.props.city.city_country}</td>
                    <td>
                        <button className="btn btn-mini">
                            <i className="fa fa-pencil"></i> Edit
                        </button>

                        <button className="btn btn-mini" onClick={this.handleDelete} >
                            <i className="fa fa-trash"></i> Delete
                        </button>
                    </td>
                </tr>
    },

    handleDelete: function() {
        this.props.onDelete( this.props.city.cityid, this.props.index );
    }
});

var CitiesToolbar = React.createClass({
    render: function() {
        return <span>
            <div id="toolbar" className="btn-toolbar">
                <button className="btn btn-small" onClick={this.props.showCityForm}>
                    <i className="fa fa-plus"></i> New city
                </button>

                <button className="btn btn-mini">
                    <i className="fa fa-pencil"></i> Edit city
                </button>

                <button className="btn btn-small" onClick={this.props.deleteCity}>
                    <i className="fa fa-trash"></i> Delete city
                </button>
            </div>

            <h2>Cities</h2>
        </span>
    },
});

var CitiesForm = React.createClass({
    getInitialState: function() {
        return {
            city: {
                cityid: "",
                city_name: "",
                city_state: "",
                city_zipcode: "",
                city_country: "",
            }
        };
    },

    render: function() {
        return <span>
        <fieldset className="rows">
            <ol>
                { this.props.city && this.props.city.cityid ?
                    <li><span className="label">City ID: </span>{this.props.city.cityid}</li>
                : ''}
                <li>
                    <label htmlFor="city_name" className="required">City: </label>
                    <input type="text" name="city_name" id="city_name" size="80" maxLength="100" value={ this.state.city ? this.state.city.city_name : "" } onChange={this.onNameChange}/>
                    <span className="required">Required</span>
                </li>
                <li>
                    <label htmlFor="city_state">State: </label>
                    <input type="text" name="city_state" id="city_state" size="80" maxLength="100" value={ this.state.city ? this.state.city.city_state : "" } onChange={this.onStateChange}/>
                </li>
                <li>
                    <label htmlFor="city_zipcode" className="required">ZIP/Postal code: </label>
                    <input type="text" name="city_zipcode" id="city_zipcode" size="20" maxLength="20" value={ this.state.city ? this.state.city.city_zipcode : "" } required="required" className="required" onChange={this.onZipcodeChange}/>
                    <span className="required">Required</span>
                </li>
                <li>
                    <label htmlFor="city_country">Country: </label>
                    <input type="text" name="city_country" id="city_country" size="80" maxLength="100" value={ this.state.city ? this.state.city.city_country : "" } onChange={this.onCountryChange} />
                </li>
            </ol>
        </fieldset>

        <fieldset className="action">
            <button className="btn" onClick={this.createOrUpdateCity} >
                <i className="fa fa-save"></i> Save
            </button>
            &nbsp;
            <button className="btn btn-mini" onClick={this.props.hideCityForm} >
                <i className="fa fa-times"></i> Cancel
            </button>
        </fieldset>
        </span>
    },

    onNameChange: function(e) {
        var city = this.state.city;
        city.city_name = e.target.value;
        this.setState({ city: city });
    },
    onStateChange: function(e) {
        var city = this.state.city;
        city.city_state = e.target.value;
        this.setState({ city: city });
    },
    onZipcodeChange: function(e) {
        var city = this.state.city;
        city.city_zipcode = e.target.value;
        this.setState({ city: city });
    },
    onCountryChange: function(e) {
        var city = this.state.city;
        city.city_country = e.target.value;
        this.setState({ city: city });
    },

    createOrUpdateCity: function() {
        var myself = this;
        var city = this.state.city;
        this.props.createOrUpdateCity(city);
    }
});

$( document ).ready(function() {
    ReactDOM.render(
        <CitiesEditor/>,
        document.getElementById('cities-editor')
    );
});
