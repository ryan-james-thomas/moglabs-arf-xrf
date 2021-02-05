%%% moglabs device class (MATLAB version)
%%% Simplifies communication with moglabs devices
%
% (c) MOGLabs 2017
% http://www.moglabs.com/
%
% v1.0 - Initial release
%
% NB: Requires Instrument Control Toolbox %%%%%
%
%
classdef mogdevice < handle
	properties
		dev;		% device object
		cx = '';	% connection string
	end
	methods
		function addr = connect(obj, addr, port)
			% connect to a MOG device: "addr" is either an IP address or the word "USB" or "COM"
			if strcmp(addr,'USB') || strncmp(addr,'COM',3)
				% connect to USB over virtual COM port
				if nargin > 2
					addr = sprintf('COM%d',port);
				end
				obj.dev = serial(addr);
			else
				% connect over ethernet using TCPIP
				if nargin < 3
					port = 7802;	% default port
				end
				obj.dev = tcpip(addr, port);
				addr = sprintf('%s:%d',addr,port);
            end
			obj.cx = addr;
			fopen(obj.dev);
		end
		function resp = ask(obj, varargin)
			% ask the device a query, ensure the response is not "ERR"
			flushinput(obj.dev);
			obj.send(sprintf(varargin{:}));
			resp = obj.recv();
            resp = resp(1:end-2);
			if strncmp(resp,'ERR',3)
				error(resp(6:end));
            end
		end
		function resp = cmd(obj, varargin)
			% send a command to the device, ensure the response is "OK"
			resp = obj.ask(varargin{:});
			if ~strncmp(resp,'OK',2)
				error('Device did not acknowledge command');
            end
            resp = resp(5:end);
		end
		function data = recv(obj)
			% receive a CRLF-terminated message
            waitfor obj.dev.BytesAvailable > 0;
            [data,~,err] = fgets(obj.dev);
            if ~isempty(err)
                error(err)
            end
		end
		function data = recv_raw(obj,n)
			% receive EXACTLY "n" bytes from the device
			data = '';
			while n > 0
				[A,m] = fread(obj.dev, n);
				n = n - m;
				data = strcat(data,A);
			end
		end
		function n = send(obj, data)
			% send a string to the device, CRLF-terminate if necessary, and return number of bytes sent
			if ~any(regexp(data,'\r\n$'))
				data = sprintf('%s\r\n',data);
			end
			n = obj.send_raw(data);
		end
		function n = send_raw(obj, data)
			% send a raw string to the device, and return number of bytes sent
			fwrite(obj.dev, data);
            n = length(data);
		end
		function delete(obj)
			% close the connection
            if isobject(obj.dev)
                if strcmp(obj.dev.Status,'open')
                    fclose(obj.dev);
                end
                delete(obj.dev);
            end
			obj.cx = '';
		end
	end
end
