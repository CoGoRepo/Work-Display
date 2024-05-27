import { onCellContextMenu, onGridReadyHandler, downloadChecklistForSelectedAsset, sideBarConfigs } from './Asset-Utility-Functions.js';
var columnDefs = [
    { headerName: "SSP", field: "ssp" },
    { headerName: "Name", field: "name" },
    { headerName: "Role", field: "role" },
    { headerName: "Operating System", field: "operatingsystem" },
    { headerName: "Build", field: "build" },
    { headerName: "IP Address", field: "ipaddress" },
    { headerName: "Asset DB-ID", field: "asset_id" },
    { headerName: "Additional Info", field: "additionalinfo", hide: true, cellRenderer: params => {
        const eDiv = document.createElement('div');
        eDiv.style.whiteSpace = 'pre-line'; // CSS property to preserve newlines
        eDiv.textContent = params.value;
        return eDiv;}
    }
];

var gridOptions = {    
    onGridReady: onGridReadyHandler,
    onCellContextMenu: onCellContextMenu,
    sideBar: sideBarConfigs,
    getContextMenuItems: function(params) {
        var result = [
            'copy', // Existing option
            {name: 'Download Checklist',
                action: function() {
                    var selectedNodes = params.api.getSelectedNodes(); // Get all selected nodes
                    selectedNodes.forEach(node => {
                        var assetId = node.data.asset_id;
                        var assetName = node.data.name;
                        var products = node.data.additionalinfo.split('\n');
                        console.log(`Asset ID: ${assetId}, Name: ${assetName}, Products: ${products}`);
                        // Now directly call the function for each selected asset
                        downloadChecklistForSelectedAsset(assetId, assetName, products);
                    });
                }
            }
        ];
        return result;
    },
    rowSelection: "multiple",
    columnDefs: columnDefs,
    defaultColDef: {
        flex: 1,
        minWidth:100,
        sortable: true,
        filter: 'agTextColumnFilter',
        floatingFilter: true,
        suppressMenu: true,
        resizable: true,
        cellStyle: {'text-align': 'center'}, 
        headerClass: 'ag-header-cell-center',
        autoHeight: true    
    },
};

// Backend endpoint to pull data for populating the grid.
const apiUrl = 'http://localhost:8000/api/assets';
//Define gridAPI so it's visibile on the global scope.
export var gridApi;

//Used to load the data in the grid.
function loadData() {
  fetch(apiUrl) // Make sure this matches the parameter name
      .then(response => {
          if (!response.ok) {
              throw new Error('Failed to fetch data');
          }
          return response.json();
      })
      .then(data => {
          // Use the new API method to set row data
          gridApi.setGridOption('rowData', data);
      })
      .catch(error => {
          console.error('Failed to load data:', error);
          // Handle the error appropriately in your UI
      });
}



document.addEventListener('DOMContentLoaded', function () {
    var gridDiv = document.querySelector('#myGrid');
    gridApi = agGrid.createGrid(gridDiv, gridOptions); // Assign the grid API to the variable
    loadData();
});





agGrid.LicenseManager.setLicenseKey("[TRIAL]_this_{AG_Charts_and_AG_Grid}_Enterprise_key_{AG-054169}_is_granted_for_evaluation_only___Use_in_production_is_not_permitted___Please_report_misuse_to_legal@ag-grid.com___For_help_with_purchasing_a_production_key_please_contact_info@ag-grid.com___You_are_granted_a_{Single_Application}_Developer_License_for_one_application_only___All_Front-End_JavaScript_developers_working_on_the_application_would_need_to_be_licensed___This_key_will_deactivate_on_{31 March 2024}____[v3]_[0102]_MTcxMTg0MzIwMDAwMA==fb01f966ded0a9f9a84dc3422fd7d82b")
