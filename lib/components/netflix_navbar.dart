import 'package:flutter/material.dart';

class NetflixNavbar extends StatefulWidget {
  final String activeCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickLocalFile;
  final VoidCallback onManageFolders;
  final int folderCount;

  const NetflixNavbar({
    super.key,
    required this.activeCategory,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onPickLocalFile,
    required this.onManageFolders,
    this.folderCount = 0,
  });

  @override
  State<NetflixNavbar> createState() => _NetflixNavbarState();
}

class _NetflixNavbarState extends State<NetflixNavbar> {
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 1000;
    final double horizontalPadding = screenWidth < 1250 ? 20.0 : 40.0;
    final double gap = screenWidth < 1250 ? 12.0 : 20.0;

    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          // Logo Red Style
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LOCAL TV',
                style: TextStyle(
                  color: const Color(0xFFE50914),
                  fontSize: isCompact ? 18 : 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'v2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: gap),

          // Categories Links
          _buildNavLink('films', 'Films'),
          SizedBox(width: gap),
          _buildNavLink('series', 'Series'),
          SizedBox(width: gap),
          _buildNavLink('local', 'Folder Film'),
          SizedBox(width: gap),

          // Manage Folders Button
          TextButton.icon(
            onPressed: widget.onManageFolders,
            icon: const Icon(Icons.folder_copy_rounded, color: Color(0xFFE50914), size: 15),
            label: Text(
              widget.folderCount > 0
                  ? 'Kelola (${widget.folderCount})'
                  : 'Folder Film',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              backgroundColor: const Color(0xFFE50914).withValues(alpha: 0.15),
              side: const BorderSide(color: Color(0xFFE50914), width: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Pick Single File
          if (screenWidth >= 1150)
            TextButton.icon(
              onPressed: widget.onPickLocalFile,
              icon: const Icon(Icons.file_open_outlined, color: Colors.white70, size: 15),
              label: const Text(
                'Buka File',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

          const Spacer(),

          // Search Field
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _isSearchOpen ? (isCompact ? 160 : 220) : 38,
            height: 38,
            decoration: BoxDecoration(
              color: _isSearchOpen ? Colors.black87 : Colors.transparent,
              border: Border.all(
                color: _isSearchOpen ? Colors.white54 : Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.search, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _isSearchOpen = !_isSearchOpen;
                        if (!_isSearchOpen) {
                          _searchController.clear();
                          widget.onSearchChanged('');
                        }
                      });
                    },
                  ),
                ),
                if (_isSearchOpen)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search titles...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(right: 8),
                      ),
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Profile Avatar (Netflix style)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'assets/images/users/1.png',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 30,
                height: 30,
                color: const Color(0xFFE50914),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(String id, String label) {
    final bool isActive = widget.activeCategory == id;
    return InkWell(
      onTap: () => widget.onCategoryChanged(id),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white60,
          fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
          fontSize: 14,
        ),
      ),
    );
  }
}
