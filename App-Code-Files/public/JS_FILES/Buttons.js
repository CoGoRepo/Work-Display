

document.getElementById('exportViewButton').addEventListener('click', function() {
    const selectedView = document.getElementById('viewSelect').value;
    if (selectedView) {
        const viewState = localStorage.getItem(selectedView);
        if (viewState) {
            const blob = new Blob([viewState], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = selectedView + '.json';
            document.body.appendChild(a); // Append the element to the document
            a.click();
            document.body.removeChild(a); // Clean up
            URL.revokeObjectURL(url); // Release the object URL
        } else {
            alert('No saved state for view: ' + selectedView);
        }
    } else {
        alert('Please select a view to export.');
    }
});


// You need to associate the label with the file input by clicking the label to trigger the input
document.querySelector('label[for="importViewInput"]').addEventListener('click', function() {
    document.getElementById('importViewInput').click();
});



document.getElementById('exportExcelButton').addEventListener('click', function() {
    // Implement the logic to export data to an Excel file
    alert('Export to Excel functionality not yet implemented.');
});
