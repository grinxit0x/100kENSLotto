// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library TimeUtils {
    uint256 constant SECONDS_PER_DAY = 86400;
    uint256 constant SECONDS_PER_YEAR = 31556926;

    function isTimeForDraw(uint256 currentTime) internal pure returns (bool) {
        (uint256 year, uint256 month, uint256 day) = timestampToDate(
            currentTime
        );
        (uint256 hour, uint256 minute, ) = timestampToTime(currentTime);

        bool isLeapYear = _isLeapYear(year);

        uint256 targetTimestamp = calculateTargetTimestamp(year, isLeapYear);

        return
            currentTime >= targetTimestamp &&
            month == 12 &&
            day == 22 &&
            hour == 9 &&
            minute == 0;
    }

    function _isLeapYear(uint256 year) internal pure returns (bool) {
        if (year % 4 == 0) {
            if (year % 100 == 0) {
                if (year % 400 == 0) {
                    return true;
                }
                return false;
            }
            return true;
        }
        return false;
    }

    function calculateTargetTimestamp(uint256 year, bool isLeapYear)
        internal
        pure
        returns (uint256)
    {
        uint256 daysUntil22December;
        uint256 targetTimestamp;
        assembly {
            daysUntil22December := add(355, isLeapYear)
            targetTimestamp := add(
                mul(sub(year, 1970), SECONDS_PER_YEAR),
                add(mul(daysUntil22December, SECONDS_PER_DAY), mul(9, 3600))
            )
        }
        return targetTimestamp;
    }

    function timestampToDate(uint256 timestamp)
        internal
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day
        )
    {
        year = 1970 + timestamp / SECONDS_PER_YEAR;
        uint256 daysSinceNewYear = (timestamp % SECONDS_PER_YEAR) /
            SECONDS_PER_DAY;

        uint256[] memory daysInMonth = new uint256[](12);
        daysInMonth[0] = 31;
        daysInMonth[1] = _isLeapYear(year) ? 29 : 28;
        daysInMonth[2] = 31;
        daysInMonth[3] = 30;
        daysInMonth[4] = 31;
        daysInMonth[5] = 30;
        daysInMonth[6] = 31;
        daysInMonth[7] = 31;
        daysInMonth[8] = 30;
        daysInMonth[9] = 31;
        daysInMonth[10] = 30;
        daysInMonth[11] = 31;

        month = 0;
        while (daysSinceNewYear >= daysInMonth[month]) {
            daysSinceNewYear -= daysInMonth[month];
            month++;
        }
        month++;
        day = daysSinceNewYear + 1;
    }

    function timestampToTime(uint256 timestamp)
        internal
        pure
        returns (
            uint256 hour,
            uint256 minute,
            uint256 second
        )
    {
        uint256 secondsInDay = timestamp % SECONDS_PER_DAY;
        hour = secondsInDay / 3600;
        minute = (secondsInDay % 3600) / 60;
        second = secondsInDay % 60;
    }
}
