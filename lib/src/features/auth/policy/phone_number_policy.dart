bool isMainlandMobileNumber(String value) =>
    RegExp(r'^1[3-9][0-9]{9}$').hasMatch(value.trim());
