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
    
    properties(Access = protected,Hidden = true)
        commands
        idx
        state
        uploadStartTime
    end
    
    properties(Constant,Hidden = true)
        STATE_IDLE = 'idle';
        STATE_SEND = 'sending';
        STATE_RECV = 'receiving';
    end
    
	methods
		function addr = connect(self, addr, port)
			% connect to a MOG device: "addr" is either an IP address or the word "USB" or "COM"
			if strcmp(addr,'USB') || strncmp(addr,'COM',3)
				% connect to USB over virtual COM port
				if nargin > 2
					addr = sprintf('COM%d',port);
				end
				self.dev = serial(addr);
			else
				% connect over ethernet using TCPIP
				if nargin < 3
					port = 7802;	% default port
				end
				self.dev = tcpclient(addr, port);
                R = version('-release');
                release_year = regexp(R,'\d+','match');
                release_year = str2double(release_year{1});
                if contains(R,'2022b') || (release_year > 2022)
                    self.dev.InputBufferSize = 2^20;
                    self.dev.OutputBufferSize = 2^20;
                end
                self.dev.configureTerminator('CR/LF');
				addr = sprintf('%s:%d',addr,port);
            end
			self.cx = addr;
		end
		function resp = ask(self, varargin)
			% ask the device a query, ensure the response is not "ERR"
			self.dev.flush('input');
			self.send(sprintf(varargin{:}));
			resp = self.recv();
			if strncmp(resp,'ERR',3)
				error(resp(6:end));
            end
		end
		function resp = cmd(self, varargin)
			% send a command to the device, ensure the response is "OK"
			resp = self.ask(varargin{:});
			if ~strncmp(resp,'OK',2)
				error('Device did not acknowledge command');
            end
            resp = resp(5:end);
		end
		function data = recv(self)
			% receive a CRLF-terminated message
            waitfor self.dev.BytesAvailable > 0;
            data = self.dev.readline();
		end
		function data = recv_raw(self,n)
			% receive EXACTLY "n" bytes from the device
            data = char(self.dev.read(n));
		end
        function n = send(self, data)
			% send a string to the device, CRLF-terminate if necessary, and return number of bytes sent
            data = regexprep(data,'\r\n$','');
			self.dev.writeline(data);
            n = length(data);
		end
		function n = send_raw(self, data)
			% send a raw string to the device, and return number of bytes sent
			self.dev.write(data);
            n = length(data);
        end
        function close(self)
            % closes the connection
            self.dev = [];
			self.cx = '';
        end
		function delete(self)
			% close the connection
            self.close();
        end
        
        function uploadCommands(self,commands)
            self.uploadStartTime = tic;
            self.commands = commands;
            self.idx = 1;
            self.state = self.STATE_SEND;
            self.dev.configureCallback('terminator',@(src,event) self.handleAsync(src,event));
            self.handleAsync;
        end
        
        function handleAsync(self,~,~)
            if strcmpi(self.state,self.STATE_SEND)
                if self.idx <= numel(self.commands)
                    self.dev.writeline(self.commands{self.idx});
                    self.idx = self.idx + 1;
                    self.state = self.STATE_RECV;
                else
                    self.state = self.STATE_IDLE;
                    self.handleAsync;
                end
            elseif strcmpi(self.state,self.STATE_RECV)
                resp = self.dev.readline();
                if strncmpi(resp(1:end-2),'ERR',3)
                    self.state = self.STATE_IDLE;
                    self.dev.configureCallback('off');
                    error(resp(6:end));
                elseif self.idx <= numel(self.commands)
                    self.state = self.STATE_SEND;
                    self.handleAsync;
                else
                    self.state = self.STATE_IDLE;
                    self.handleAsync;
                end
            else
                self.dev.configureCallback('off');
                t = toc(self.uploadStartTime);
                fprintf(1,'Table upload complete (%d instructions in %.1f s)\n',self.idx-1,t);
%                 [R,err] = self.checkClocks;
%                 if ~R
%                     warning('One or more clocks are unlocked: %s',err);
%                 end
            end
        end

        function self = blocking_upload(self)
            self.uploadStartTime = tic;
            self.idx = 1;
            for nn = 1:numel(self.commands)
                self.send(self.commands{nn});
                resp = self.dev.readline();
                if strncmpi(resp(1:end-2),'ERR',3)
                    error(resp(6:end));
                end
            end
            t = toc(self.uploadStartTime);
            fprintf(1,'Table upload complete (%d instructions in %.1f s)\n',numel(self.commands),t);
        end
        
        function [R,err] = checkClocks(self)
            %CHECKCLOCKS Checks the ARF clocks to ensure they are locked
            %
            %   [R,ERR] = MOG.CHECKCLOCKS() Checks to see if the ARF clocks
            %   are locked. Returns R = TRUE if all clocks are locked, R =
            %   FALSE if one is not locked, and ERR contains an error
            %   message
            s = self.ask('clkdiag');
            s = strsplit(s,',');
            R = true;
            err = '';
            for nn = 1:numel(s)
                r = strfind(s{nn},'LOCKED');
                if isempty(r)
                    R = false;
                    switch nn
                        case 1
                            err = sprintf('Reference clock unlocked: %s',s{nn});
                        case 2
                            err = sprintf('System clock unlocked: %s',s{nn});
                        case 3
                            err = sprintf('DDS clock unlocked: %s',s{nn});
                        case 4
                            err = sprintf('SYNC clock unlocked: %s',s{nn});
                        otherwise
                            err = sprintf('Unspecified clock unlocked: %s',s{nn});
                    end
                    break
                end
            end
            
        end
	end
end
