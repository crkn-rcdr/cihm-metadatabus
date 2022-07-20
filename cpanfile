requires 'Log::Log4perl';
requires 'common::sense';
requires 'MIME::Types';
requires 'Class::Singleton';
requires 'Config::General';
requires 'DateTime';
requires 'Date::Manip';
requires 'Date::Parse';
requires 'JSON';
requires 'JSON::Parse';
requires 'Types::Standard';
requires 'Role::REST::Client';
requires 'Crypt::JWT';
requires 'Switch';
requires 'Archive::BagIt';
requires 'Filesys::Df';
requires 'Coro::Semaphore';
requires 'AnyEvent';
requires 'AnyEvent::Fork';
requires 'AnyEvent::Fork::Pool';
requires 'Furl';
requires 'XML::LibXSLT';
requires 'XML::LibXML';
requires 'IO::AIO';
requires 'IO::Socket::SSL';
requires 'List::Compare';

# Used by CIHM::Meta::dmd::flatten
requires 'MARC::File::XML';

# Used by dmdtask
requires 'Text::CSV';

# Used by ocrtask
requires 'DateTime::Format::ISO8601';
requires 'Poppler';

# Used by Smelter
requires 'Image::Magick', '== 6.9.12';
