import { gridApi } from './load-asset-grid.js';


export const onGridReadyHandler = (params) => {
    const urlParams = new URLSearchParams(window.location.search);
    const sspFilter = urlParams.get('ssp'); // Retrieve SSP filter from URL if exists
    const statusFilter = urlParams.get('vstatus'); // Retrieve Status filter from URL if exists

    const filterModel = {};
    if (sspFilter) { // Apply SSP filter if it exists
        filterModel.ssp = {
            type: 'equals',
            filter: sspFilter
        };
    }
    if (statusFilter) { // Apply Status filter if it exists
      filterModel.status = {
          type: 'notContains',
          filter: statusFilter
      };
  }
    params.api.setFilterModel(filterModel);
};

export function onCellContextMenu(params) {
  var rowNode = params.node;
  var alreadySelected = rowNode.isSelected();
  // Select the row if it's not already selected
  if (!alreadySelected) {
      params.api.deselectAll();
      rowNode.setSelected(true, true);
  }
}

export const sideBarConfigs = {
    toolPanels: [
      {
        id: 'columns',
        labelDefault: 'Columns',
        labelKey: 'columns',
        iconKey: 'columns',
        toolPanel: 'agColumnsToolPanel',
        toolPanelParams: {
          suppressRowGroups: true,
          suppressValues: true,
          suppressPivots: true,
          suppressPivotMode: true,
          suppressSideButtons: true,
          suppressColumnFilter: true,
          suppressColumnSelectAll: true,
          suppressColumnExpandAll: true,
        },
      },
      {
        id: 'filters',
        labelDefault: 'Filters',
        labelKey: 'filters',
        iconKey: 'filter',
        toolPanel: 'agFiltersToolPanel',
      }
    ]
  };

export function downloadChecklistForSelectedAsset(assetId, assetName, products) {
  fetch('/api/generate-checklist', {
      method: 'POST',
      headers: {
          'Content-Type': 'application/json',
      },
      body: JSON.stringify({ assetId, assetName, products }),
  })
  .then(response => response.blob())
  .then(blob => {
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${assetName}-checklist.cklb`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
  })
  .catch(error => console.error('Download failed:', error));
}


document.getElementById('saveViewButton').addEventListener('click', function() {
  const viewName = prompt('Enter the name for the new view:');
  if (viewName) {
      const viewState = {
          columnState: gridApi.getColumnState(),
          filterModel: gridApi.getFilterModel(),
          // Add other states as needed, like sortModel
      };
      // Save the view state to localStorage or a server
      localStorage.setItem(viewName, JSON.stringify(viewState));

      // UI: Add the new view to the select dropdown
      const viewSelect = document.getElementById('viewSelect');
      const option = new Option(viewName, viewName.toLowerCase().replace(/\s+/g, '_'));
      viewSelect.add(option);
      viewSelect.value = option.value; // Select the newly added option
  }
});

document.getElementById('importViewInput').addEventListener('change', function(event) {
  const file = event.target.files[0];
  if (file) {
      const reader = new FileReader();
      reader.onload = function(e) {
          const viewState = JSON.parse(e.target.result);
          gridApi.setColumnState(viewState.columnState);
          gridApi.setFilterModel(viewState.filterModel);
          // Apply other states as needed

          // Update the UI or perform additional actions as necessary
          // For example, adding the imported view to a select dropdown for future reference

          alert('Imported view from: ' + file.name);
      };
      reader.readAsText(file);

      // Reset file input to allow re-importing the same file if needed
      event.target.value = '';
  }
});